import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:permission_handler/permission_handler.dart';

/// Represents a single SMS message
class BankSmsMessage {
  final String address;
  final String body;
  final DateTime date;

  BankSmsMessage({
    required this.address,
    required this.body,
    required this.date,
  });
}

/// Service to read SMS messages (Android only)
class SmsService {
  static final SmsService _instance = SmsService._internal();
  factory SmsService() => _instance;
  SmsService._internal();

  final SmsQuery _query = SmsQuery();

  /// Last error message for UI display
  String? lastError;

  /// Bank sender IDs to filter
  static const List<String> bankSenders = [
    // Axis Bank
    'AX-AXISBANK',
    'VM-AXISBK',
    'AD-AXISBK',
    'AXISBK',
    'AxisBk',
    // HDFC Bank
    'AD-HDFCBK',
    'VM-HDFCBK',
    'AX-HDFCBK',
    'HDFCBK',
    'HDFCBk',
    // ICICI Bank
    'VM-ICICIB',
    'AX-ICICIB',
    'AD-ICICIB',
    'ICICIB',
    'ICICIBk',
    // SBI
    'VM-SBIINB',
    'AX-SBIINB',
    'AD-SBIINB',
    'SBIINB',
    'SBIBnk',
    // Kotak
    'VM-KOTAKB',
    'AD-KOTAKB',
    'KOTAKB',
    // Yes Bank
    'VM-YESBK',
    'AD-YESBK',
    'YESBK',
    // IndusInd
    'VM-INDBNK',
    'AD-INDBNK',
    'INDBNK',
  ];

  /// Check if platform supports SMS reading
  bool get isPlatformSupported => Platform.isAndroid;

  /// Check if SMS permission is granted
  Future<bool> hasPermission() async {
    if (!isPlatformSupported) return false;
    try {
      final status = await Permission.sms.status;
      debugPrint('SMS permission status: $status');
      return status.isGranted;
    } catch (e) {
      debugPrint('Error checking SMS permission: $e');
      lastError = 'Plugin not initialized. Please restart the app completely.';
      rethrow;
    }
  }

  /// Request SMS permission
  Future<bool> requestPermission() async {
    if (!isPlatformSupported) return false;
    try {
      debugPrint('Requesting SMS permission...');
      final status = await Permission.sms.request();
      debugPrint('Permission result: $status');
      return status.isGranted;
    } catch (e) {
      debugPrint('Error requesting SMS permission: $e');
      if (e.toString().contains('MissingPluginException')) {
        lastError = 'App needs full restart. Please close and reopen the app.';
      } else {
        lastError = 'Permission request failed: $e';
      }
      rethrow;
    }
  }

  /// Check if permission is permanently denied
  Future<bool> isPermissionPermanentlyDenied() async {
    if (!isPlatformSupported) return false;
    try {
      final status = await Permission.sms.status;
      return status.isPermanentlyDenied;
    } catch (e) {
      debugPrint('Error checking permission denied status: $e');
      return false;
    }
  }

  /// Open app settings for permission
  Future<bool> openSettings() async {
    return await openAppSettings();
  }

  /// Read SMS messages from bank senders
  /// Returns messages from the last [daysToFetch] days
  /// If [sinceDate] is provided, only returns messages after that timestamp
  Future<List<BankSmsMessage>> readBankSms({
    int daysToFetch = 365,
    DateTime? sinceDate,
  }) async {
    if (!isPlatformSupported) {
      debugPrint('SMS reading not supported on this platform');
      return [];
    }

    debugPrint('Starting SMS read...');

    try {
      debugPrint('Fetching inbox SMS...');
      final messages = await _query.querySms(
        kinds: [SmsQueryKind.inbox],
        count: 5000, // Fetch up to 5000 messages
      );

      debugPrint('Total SMS messages found: ${messages.length}');

      final cutoffDate = sinceDate ??
          DateTime.now().subtract(Duration(days: daysToFetch));
      final filteredMessages = <BankSmsMessage>[];

      for (final msg in messages) {
        final address = msg.address ?? '';
        final body = msg.body ?? '';
        final date = msg.date;

        // Skip if no date
        if (date == null) continue;

        // Skip old messages
        if (date.isBefore(cutoffDate)) continue;

        // Check if sender is a bank
        if (_isBankSender(address)) {
          filteredMessages.add(BankSmsMessage(
            address: address,
            body: body,
            date: date,
          ));
        }
      }

      debugPrint('Found ${filteredMessages.length} bank SMS messages');
      return filteredMessages;
    } catch (e, stack) {
      debugPrint('Error reading SMS: $e');
      debugPrint('Stack trace: $stack');
      lastError = 'Failed to read SMS: $e';
      return [];
    }
  }

  /// Check if the sender address matches any known bank sender
  bool _isBankSender(String address) {
    final upperAddress = address.toUpperCase();
    for (final sender in bankSenders) {
      if (upperAddress.contains(sender.toUpperCase())) {
        return true;
      }
    }
    return false;
  }

  /// Extract bank name from sender address
  String? getBankNameFromAddress(String address) {
    final upperAddress = address.toUpperCase();

    if (upperAddress.contains('AXIS')) {
      return 'Axis Bank';
    } else if (upperAddress.contains('HDFC')) {
      return 'HDFC Bank';
    } else if (upperAddress.contains('ICICI')) {
      return 'ICICI Bank';
    } else if (upperAddress.contains('SBI')) {
      return 'SBI';
    } else if (upperAddress.contains('KOTAK')) {
      return 'Kotak Mahindra Bank';
    } else if (upperAddress.contains('YES')) {
      return 'Yes Bank';
    } else if (upperAddress.contains('IND')) {
      return 'IndusInd Bank';
    }

    return null;
  }
}
