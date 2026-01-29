import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/subscription.dart';
import '../services/database_service.dart';
import '../services/sms_service.dart';
import '../services/subscription_parser_service.dart';

const String _dismissedDuplicatesKey = 'dismissed_duplicate_platforms';

enum ScanStatus {
  idle,
  requestingPermission,
  scanning,
  completed,
  error,
  permissionDenied,
}

class SubscriptionProvider with ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();
  final SmsService _smsService = SmsService();
  final SubscriptionParserService _parserService = SubscriptionParserService();

  List<Subscription> _subscriptions = [];
  List<List<Subscription>> _potentialDuplicates = [];
  Set<String> _dismissedDuplicatePlatforms = {};
  ScanStatus _scanStatus = ScanStatus.idle;
  String? _errorMessage;
  int _scanProgress = 0;
  int _scanTotal = 0;
  int _newSubscriptionsFound = 0;

  List<Subscription> get subscriptions => _subscriptions;
  List<Subscription> get activeSubscriptions =>
      _subscriptions.where((s) => s.isActive).toList();
  List<List<Subscription>> get potentialDuplicates => _potentialDuplicates;
  ScanStatus get scanStatus => _scanStatus;
  String? get errorMessage => _errorMessage;
  int get scanProgress => _scanProgress;
  int get scanTotal => _scanTotal;
  int get newSubscriptionsFound => _newSubscriptionsFound;

  /// Check if SMS scanning is supported (Android only)
  bool get isSmsSupported => Platform.isAndroid;

  /// Calculate total monthly cost of all active subscriptions
  double get totalMonthlyCost {
    return activeSubscriptions.fold(0.0, (sum, sub) => sum + sub.monthlyCost);
  }

  /// Calculate remaining payments for this month (subscriptions not yet paid)
  double get remainingThisMonth {
    final now = DateTime.now();

    return activeSubscriptions.fold(0.0, (sum, sub) {
      final nextDate = sub.nextPaymentDate;
      if (nextDate == null) return sum;

      // Check if next payment is in current month and hasn't passed
      if (nextDate.year == now.year &&
          nextDate.month == now.month &&
          nextDate.day >= now.day) {
        return sum + sub.amount;
      }
      return sum;
    });
  }

  /// Calculate total payments for next month
  double get nextMonthTotal {
    final now = DateTime.now();
    final nextMonth = now.month == 12 ? 1 : now.month + 1;
    final nextMonthYear = now.month == 12 ? now.year + 1 : now.year;

    return activeSubscriptions.fold(0.0, (sum, sub) {
      final nextDate = sub.nextPaymentDate;
      if (nextDate == null) return sum;

      // Check if nextPaymentDate falls in next month
      if (nextDate.year == nextMonthYear && nextDate.month == nextMonth) {
        return sum + sub.amount;
      }

      // For monthly subscriptions with nextPaymentDate in current month,
      // they will also have a payment next month
      if (sub.frequency == SubscriptionFrequency.monthly &&
          nextDate.year == now.year &&
          nextDate.month == now.month) {
        return sum + sub.amount;
      }

      return sum;
    });
  }

  /// Get subscriptions grouped by category
  Map<SubscriptionCategory, List<Subscription>> get subscriptionsByCategory {
    final grouped = <SubscriptionCategory, List<Subscription>>{};
    for (final sub in activeSubscriptions) {
      grouped.putIfAbsent(sub.category, () => []).add(sub);
    }
    return grouped;
  }

  /// Load subscriptions from database
  Future<void> loadSubscriptions() async {
    debugPrint('[LOAD] loadSubscriptions called, current scanStatus=$_scanStatus');
    try {
      // Load dismissed platforms from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      _dismissedDuplicatePlatforms =
          (prefs.getStringList(_dismissedDuplicatesKey) ?? []).toSet();

      _subscriptions = await _databaseService.getAllSubscriptions();
      final allDuplicates = await _databaseService.findPotentialDuplicates();

      // Filter out dismissed platforms
      _potentialDuplicates = allDuplicates
          .where((group) => !_dismissedDuplicatePlatforms
              .contains(group.first.platform.toLowerCase()))
          .toList();

      debugPrint('[LOAD] Loaded ${_subscriptions.length} subscriptions, ${_potentialDuplicates.length} duplicate groups, notifying...');
      notifyListeners();
    } catch (e) {
      debugPrint('[LOAD] Error loading subscriptions: $e');
    }
  }

  /// Merge duplicate subscriptions (keep most recent, delete others)
  Future<void> mergeSubscriptions(List<Subscription> subscriptions) async {
    try {
      await _databaseService.mergeSubscriptions(subscriptions);
      await loadSubscriptions();
    } catch (e) {
      debugPrint('Error merging subscriptions: $e');
      rethrow;
    }
  }

  /// Dismiss a duplicate suggestion (user says they're different)
  Future<void> dismissDuplicateSuggestion(List<Subscription> group) async {
    if (group.isEmpty) return;

    // Add platform to dismissed list
    final platform = group.first.platform.toLowerCase();
    _dismissedDuplicatePlatforms.add(platform);

    // Save to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _dismissedDuplicatesKey, _dismissedDuplicatePlatforms.toList());

    // Remove from current list
    _potentialDuplicates.removeWhere((g) =>
        g.isNotEmpty && g.first.platform.toLowerCase() == platform);
    notifyListeners();
  }

  /// Check if SMS permission is granted
  Future<bool> hasPermission() async {
    try {
      return await _smsService.hasPermission();
    } catch (e) {
      _errorMessage = _smsService.lastError ?? 'Failed to check permission: $e';
      _scanStatus = ScanStatus.error;
      notifyListeners();
      return false;
    }
  }

  /// Request SMS permission
  Future<bool> requestPermission() async {
    _scanStatus = ScanStatus.requestingPermission;
    notifyListeners();

    try {
      final granted = await _smsService.requestPermission();
      if (!granted) {
        final isPermanentlyDenied =
            await _smsService.isPermissionPermanentlyDenied();
        _scanStatus =
            isPermanentlyDenied ? ScanStatus.permissionDenied : ScanStatus.idle;
        notifyListeners();
      }
      return granted;
    } catch (e) {
      _errorMessage = _smsService.lastError ?? 'Permission request failed: $e';
      _scanStatus = ScanStatus.error;
      notifyListeners();
      return false;
    }
  }

  /// Open app settings for permission
  Future<void> openSettings() async {
    await _smsService.openSettings();
  }

  /// Scan SMS messages for subscriptions
  /// If clearExisting is true (long press), clears all subscriptions first
  /// If clearExisting is false (normal tap), only adds new subscriptions
  Future<void> scanSms({int daysToFetch = 365, bool clearExisting = false}) async {
    debugPrint('[SCAN] scanSms called, clearExisting=$clearExisting');

    if (!isSmsSupported) {
      _errorMessage = 'SMS scanning is only available on Android';
      _scanStatus = ScanStatus.error;
      notifyListeners();
      return;
    }

    // Set scanning status IMMEDIATELY to show loading UI
    _scanStatus = ScanStatus.scanning;
    _scanProgress = 0;
    _scanTotal = 0;
    _newSubscriptionsFound = 0;
    _errorMessage = null;
    if (clearExisting) {
      _subscriptions = []; // Only clear list if doing full refresh
      _potentialDuplicates = [];
      // Also clear dismissed duplicate preferences so user sees suggestions again
      _dismissedDuplicatePlatforms.clear();
      SharedPreferences.getInstance().then((prefs) {
        prefs.remove(_dismissedDuplicatesKey);
      });
    }
    debugPrint('[SCAN] Status set to SCANNING, clearExisting=$clearExisting, notifying...');
    notifyListeners();
    debugPrint('[SCAN] Notified listeners');

    // Check permission
    debugPrint('Checking SMS permission...');
    bool hasPermissionGranted;
    try {
      hasPermissionGranted = await _smsService.hasPermission();
    } catch (e) {
      _errorMessage = _smsService.lastError ?? 'Failed to check permission: $e';
      _scanStatus = ScanStatus.error;
      notifyListeners();
      return;
    }
    debugPrint('Has permission: $hasPermissionGranted');

    if (!hasPermissionGranted) {
      debugPrint('Requesting permission...');
      try {
        final granted = await _smsService.requestPermission();
        debugPrint('Permission granted: $granted');

        if (!granted) {
          final isPermanentlyDenied =
              await _smsService.isPermissionPermanentlyDenied();
          _scanStatus =
              isPermanentlyDenied ? ScanStatus.permissionDenied : ScanStatus.idle;
          notifyListeners();
          debugPrint('Permission denied, returning');
          return;
        }
      } catch (e) {
        _errorMessage = _smsService.lastError ?? 'Permission request failed: $e';
        _scanStatus = ScanStatus.error;
        notifyListeners();
        return;
      }
    }

    try {
      // Clear only SMS-scanned subscriptions if doing full refresh
      // This preserves manually added and cloud-synced subscriptions
      if (clearExisting) {
        debugPrint('[SCAN] Clearing SMS-scanned subscriptions (preserving cloud-synced)...');
        await _databaseService.clearSmsScannedSubscriptions();
      }

      debugPrint('[SCAN] Starting SMS parsing...');
      final parsed = await _parserService.parseSubscriptions(
        daysToFetch: daysToFetch,
        onProgress: (current, total) {
          _scanProgress = current;
          _scanTotal = total;
          notifyListeners();
        },
      );

      debugPrint('Parsed ${parsed.length} subscriptions');

      // Save new subscriptions to database
      for (final parsedSub in parsed) {
        final dayOfMonth = parsedSub.paymentDate.day;
        debugPrint('Processing: ${parsedSub.platform} - ₹${parsedSub.amount} - Day $dayOfMonth');

        // Check if SMS hash already exists (exact duplicate message)
        final exists = await _databaseService.smsHashExists(parsedSub.smsHash);
        if (!exists) {
          // Check if same platform + amount + day of month exists
          final existingSubscription =
              await _databaseService.getSubscriptionByPlatformAmountAndDay(
                  parsedSub.platform, parsedSub.amount, dayOfMonth);

          if (existingSubscription != null) {
            // Update existing subscription with new payment date
            final updated = existingSubscription.copyWith(
              lastPaymentDate: parsedSub.paymentDate,
              nextPaymentDate: parsedSub.toSubscription().nextPaymentDate,
              bankName: parsedSub.bankName,
              smsHash: parsedSub.smsHash,
            );
            await _databaseService.updateSubscription(updated);
            debugPrint('Updated: ${parsedSub.platform} - Day $dayOfMonth');
          } else {
            // Insert new subscription (different platform/amount/day)
            final subscription = parsedSub.toSubscription();
            await _databaseService.insertSubscription(subscription);
            _newSubscriptionsFound++;
            debugPrint('Added new: ${parsedSub.platform} - ₹${parsedSub.amount} - Day $dayOfMonth');
          }
        }
      }

      // Reload subscriptions
      debugPrint('[SCAN] About to load subscriptions from DB...');
      await loadSubscriptions();
      debugPrint('[SCAN] Loaded ${_subscriptions.length} subscriptions from DB');

      _scanStatus = ScanStatus.completed;
      debugPrint('[SCAN] Status set to COMPLETED, notifying...');
      notifyListeners();
      debugPrint('[SCAN] Scan completed. Found $_newSubscriptionsFound new subscriptions');
    } catch (e, stack) {
      debugPrint('Error scanning SMS: $e');
      debugPrint('Stack: $stack');
      _errorMessage = 'Failed to scan: $e';
      _scanStatus = ScanStatus.error;
      notifyListeners();
    }
  }

  /// Add a subscription manually
  Future<void> addSubscription(Subscription subscription) async {
    try {
      await _databaseService.insertSubscription(subscription);
      await loadSubscriptions();
    } catch (e) {
      debugPrint('Error adding subscription: $e');
      rethrow;
    }
  }

  /// Update a subscription
  Future<void> updateSubscription(Subscription subscription) async {
    try {
      await _databaseService.updateSubscription(subscription);
      await loadSubscriptions();
    } catch (e) {
      debugPrint('Error updating subscription: $e');
      rethrow;
    }
  }

  /// Delete a subscription
  Future<void> deleteSubscription(int id) async {
    try {
      await _databaseService.softDeleteSubscription(id);
      await loadSubscriptions();
    } catch (e) {
      debugPrint('Error deleting subscription: $e');
      rethrow;
    }
  }

  /// Toggle subscription active status
  Future<void> toggleSubscriptionActive(int id, bool isActive) async {
    try {
      await _databaseService.toggleSubscriptionActive(id, isActive);
      await loadSubscriptions();
    } catch (e) {
      debugPrint('Error toggling subscription: $e');
      rethrow;
    }
  }

  /// Reset scan status
  void resetScanStatus() {
    _scanStatus = ScanStatus.idle;
    _scanProgress = 0;
    _scanTotal = 0;
    _newSubscriptionsFound = 0;
    _errorMessage = null;
    notifyListeners();
  }
}
