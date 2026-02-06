import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/subscription.dart';
import '../services/database_service.dart';
import '../services/sms_service.dart';
import '../services/subscription_parser_service.dart';

const String _dismissedDuplicatesKey = 'dismissed_duplicate_platforms';
const String _mergeResolvedUuidsKey = 'merge_resolved_uuids';
const String _lastScanTimestampKey = 'last_sms_scan_timestamp';

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
  Set<String> _mergeResolvedUuids = {};
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

  /// Calculate monthly cost for a specific category
  double monthlyCostForCategory(SubscriptionCategory category) {
    return activeSubscriptions
        .where((s) => s.category == category)
        .fold(0.0, (sum, sub) => sum + sub.monthlyCost);
  }

  /// Calculate remaining this month for a specific category
  double remainingThisMonthForCategory(SubscriptionCategory category) {
    final now = DateTime.now();
    return activeSubscriptions.where((s) => s.category == category).fold(0.0,
        (sum, sub) {
      final nextDate = sub.nextPaymentDate;
      if (nextDate == null) return sum;
      if (nextDate.year == now.year &&
          nextDate.month == now.month &&
          nextDate.day >= now.day) {
        return sum + sub.amount;
      }
      return sum;
    });
  }

  /// Calculate next month total for a specific category
  double nextMonthTotalForCategory(SubscriptionCategory category) {
    final now = DateTime.now();
    final nextMonth = now.month == 12 ? 1 : now.month + 1;
    final nextMonthYear = now.month == 12 ? now.year + 1 : now.year;

    return activeSubscriptions.where((s) => s.category == category).fold(0.0,
        (sum, sub) {
      final nextDate = sub.nextPaymentDate;
      if (nextDate == null) return sum;
      if (nextDate.year == nextMonthYear && nextDate.month == nextMonth) {
        return sum + sub.amount;
      }
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
    try {
      // Load dismissed platforms and merge-resolved UUIDs from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      _dismissedDuplicatePlatforms =
          (prefs.getStringList(_dismissedDuplicatesKey) ?? []).toSet();
      _mergeResolvedUuids =
          (prefs.getStringList(_mergeResolvedUuidsKey) ?? []).toSet();

      _subscriptions = await _databaseService.getAllSubscriptions();
      final allDuplicates = await _databaseService.findPotentialDuplicates();

      // Filter out dismissed platforms, then filter out merge-resolved UUIDs,
      // and only keep groups that still have 2+ items
      _potentialDuplicates = allDuplicates
          .where((group) => !_dismissedDuplicatePlatforms
              .contains(group.first.platform.toLowerCase()))
          .map((group) => group
              .where((s) => !_mergeResolvedUuids.contains(s.uuid))
              .toList())
          .where((group) => group.length >= 2)
          .toList();

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading subscriptions: $e');
    }
  }

  /// Merge duplicate subscriptions (keep most recent, delete others)
  /// Marks all participating UUIDs as resolved (persisted in SharedPreferences)
  /// Optionally overrides frequency and category on the kept subscription.
  Future<void> mergeSubscriptions(
    List<Subscription> subscriptions, {
    SubscriptionFrequency? frequency,
    SubscriptionCategory? category,
  }) async {
    if (subscriptions.isEmpty) return;

    // Mark all participating UUIDs as resolved so they don't reappear
    _mergeResolvedUuids.addAll(subscriptions.map((s) => s.uuid));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _mergeResolvedUuidsKey, _mergeResolvedUuids.toList());

    await _databaseService.mergeSubscriptions(subscriptions);

    // Apply frequency/category overrides to the kept subscription (most recent)
    if (frequency != null || category != null) {
      final sorted = List<Subscription>.from(subscriptions)
        ..sort((a, b) => b.lastPaymentDate.compareTo(a.lastPaymentDate));
      final kept = sorted.first;
      if (kept.id != null) {
        final updated = kept.copyWith(
          frequency: frequency,
          category: category,
          nextPaymentDate: frequency != null
              ? DateTime(
                  kept.lastPaymentDate.year,
                  kept.lastPaymentDate.month + frequency.monthsPerCycle,
                  kept.lastPaymentDate.day,
                )
              : null,
        );
        await _databaseService.updateSubscription(updated);
      }
    }

    await loadSubscriptions();
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
      // Clear dismissed + merge-resolved preferences so user sees suggestions again
      _dismissedDuplicatePlatforms.clear();
      _mergeResolvedUuids.clear();
      SharedPreferences.getInstance().then((prefs) {
        prefs.remove(_dismissedDuplicatesKey);
        prefs.remove(_mergeResolvedUuidsKey);
        prefs.remove(_lastScanTimestampKey);
      });
    }
    notifyListeners();

    // Check permission
    bool hasPermissionGranted;
    try {
      hasPermissionGranted = await _smsService.hasPermission();
    } catch (e) {
      _errorMessage = _smsService.lastError ?? 'Failed to check permission: $e';
      _scanStatus = ScanStatus.error;
      notifyListeners();
      return;
    }

    if (!hasPermissionGranted) {
      try {
        final granted = await _smsService.requestPermission();

        if (!granted) {
          final isPermanentlyDenied =
              await _smsService.isPermissionPermanentlyDenied();
          _scanStatus =
              isPermanentlyDenied ? ScanStatus.permissionDenied : ScanStatus.idle;
          notifyListeners();
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
      // Clear all subscriptions if doing full refresh
      if (clearExisting) {
        await _databaseService.clearAllSubscriptions();
      }

      final parsed = await _parserService.parseSubscriptions(
        daysToFetch: daysToFetch,
        onProgress: (current, total) {
          _scanProgress = current;
          _scanTotal = total;
          notifyListeners();
        },
      );

      // Save new subscriptions to database
      for (final parsedSub in parsed) {
        final dayOfMonth = parsedSub.paymentDate.day;

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
          } else {
            // Insert new subscription (different platform/amount/day)
            final subscription = parsedSub.toSubscription();
            await _databaseService.insertSubscription(subscription);
            _newSubscriptionsFound++;
          }
        }
      }

      // Save last scan timestamp
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _lastScanTimestampKey, DateTime.now().toIso8601String());

      // Reload subscriptions
      await loadSubscriptions();

      _scanStatus = ScanStatus.completed;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to scan: $e';
      _scanStatus = ScanStatus.error;
      notifyListeners();
    }
  }

  /// Silently check for new SMS since last scan and update payment dates.
  /// Called automatically when the subscriptions screen opens.
  Future<void> updateFromNewMessages() async {
    if (!isSmsSupported) return;

    final prefs = await SharedPreferences.getInstance();
    final lastScanStr = prefs.getString(_lastScanTimestampKey);

    // No previous scan — nothing to update incrementally
    if (lastScanStr == null) {
      await loadSubscriptions();
      return;
    }

    final lastScanDate = DateTime.tryParse(lastScanStr);
    if (lastScanDate == null) {
      await loadSubscriptions();
      return;
    }

    // Check permission silently — don't prompt
    bool hasPermissionGranted;
    try {
      hasPermissionGranted = await _smsService.hasPermission();
    } catch (e) {
      await loadSubscriptions();
      return;
    }
    if (!hasPermissionGranted) {
      await loadSubscriptions();
      return;
    }

    try {
      final parsed = await _parserService.parseSubscriptions(
        sinceDate: lastScanDate,
      );

      if (parsed.isEmpty) {
        await loadSubscriptions();
        return;
      }

      for (final parsedSub in parsed) {
        final dayOfMonth = parsedSub.paymentDate.day;

        final exists = await _databaseService.smsHashExists(parsedSub.smsHash);
        if (!exists) {
          final existingSubscription =
              await _databaseService.getSubscriptionByPlatformAmountAndDay(
                  parsedSub.platform, parsedSub.amount, dayOfMonth);

          if (existingSubscription != null) {
            // Update existing subscription with newer payment date
            if (parsedSub.paymentDate
                .isAfter(existingSubscription.lastPaymentDate)) {
              final updated = existingSubscription.copyWith(
                lastPaymentDate: parsedSub.paymentDate,
                nextPaymentDate: parsedSub.toSubscription().nextPaymentDate,
                bankName: parsedSub.bankName,
                smsHash: parsedSub.smsHash,
              );
              await _databaseService.updateSubscription(updated);
            }
          } else {
            final subscription = parsedSub.toSubscription();
            await _databaseService.insertSubscription(subscription);
          }
        }
      }

      // Update last scan timestamp
      await prefs.setString(
          _lastScanTimestampKey, DateTime.now().toIso8601String());

      await loadSubscriptions();
    } catch (e) {
      debugPrint('Error updating from new messages: $e');
      await loadSubscriptions();
    }
  }

  /// Add a subscription manually
  Future<void> addSubscription(Subscription subscription) async {
    await _databaseService.insertSubscription(subscription);
    await loadSubscriptions();
  }

  /// Update a subscription
  Future<void> updateSubscription(Subscription subscription) async {
    await _databaseService.updateSubscription(subscription);
    await loadSubscriptions();
  }

  /// Delete a subscription
  Future<void> deleteSubscription(int id) async {
    await _databaseService.softDeleteSubscription(id);
    await loadSubscriptions();
  }

  /// Toggle subscription active status
  Future<void> toggleSubscriptionActive(int id, bool isActive) async {
    await _databaseService.toggleSubscriptionActive(id, isActive);
    await loadSubscriptions();
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
