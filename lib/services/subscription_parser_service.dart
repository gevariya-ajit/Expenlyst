import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../models/subscription.dart';
import 'sms_service.dart' show SmsService, BankSmsMessage;

/// Result from parsing an SMS message
class ParsedSubscription {
  final String platform;
  final double amount;
  final DateTime paymentDate;
  final SubscriptionFrequency frequency;
  final SubscriptionCategory category;
  final String? bankName;
  final String smsHash;

  ParsedSubscription({
    required this.platform,
    required this.amount,
    required this.paymentDate,
    required this.frequency,
    required this.category,
    this.bankName,
    required this.smsHash,
  });

  ParsedSubscription copyWith({SubscriptionFrequency? frequency}) {
    return ParsedSubscription(
      platform: platform,
      amount: amount,
      paymentDate: paymentDate,
      frequency: frequency ?? this.frequency,
      category: category,
      bankName: bankName,
      smsHash: smsHash,
    );
  }

  Subscription toSubscription() {
    return Subscription(
      platform: platform,
      category: category,
      amount: amount,
      frequency: frequency,
      lastPaymentDate: paymentDate,
      nextPaymentDate: _calculateNextPaymentDate(),
      bankName: bankName,
      smsHash: smsHash,
    );
  }

  DateTime _calculateNextPaymentDate() {
    return DateTime(
      paymentDate.year,
      paymentDate.month + frequency.monthsPerCycle,
      paymentDate.day,
    );
  }
}

/// Service to parse subscription information from bank SMS messages
class SubscriptionParserService {
  static final SubscriptionParserService _instance =
      SubscriptionParserService._internal();
  factory SubscriptionParserService() => _instance;
  SubscriptionParserService._internal();

  final SmsService _smsService = SmsService();

  /// OTT Platform aliases for detection
  static const Map<String, List<String>> platformAliases = {
    'Netflix': ['netflix', 'netflix.com', 'netflixinc', 'netflix inc'],
    'Amazon Prime': [
      'amazon prime',
      'amazon pay',
      'prime video',
      'amazonprime',
      'amazon.in',
      'amazon seller',
    ],
    'Disney+ Hotstar': [
      'hotstar',
      'disney hotstar',
      'disneyplus',
      'disney+',
      'disney plus',
    ],
    'Zee5': ['zee5', 'zee 5', 'zee5.com'],
    'SonyLIV': ['sonyliv', 'sony liv', 'www sonyliv com', 'sony liv com'],
    'YouTube Premium': [
      'yt music',
      'youtube music',
      'youtube premium',
      'google youtube',
      'youtube.com',
    ],
    'KuKu FM': ['kukufm', 'kuku fm', 'kuku.fm', 'kukufm.com'],
    'Tangy TV': ['tangytv', 'tangy tv', 'tangytvquickcuts'],
    'Spotify': ['spotify', 'spotify.com', 'spotify ab'],
    'Apple Music': ['apple music', 'apple media services', 'apple.com/bill'],
    'JioCinema': ['jiocinema', 'jio cinema'],
    'MX Player': ['mx player', 'mxplayer'],
    'Voot': ['voot', 'voot.com'],
    'ALTBalaji': ['altbalaji', 'alt balaji'],
    'Eros Now': ['erosnow', 'eros now'],
    'Lionsgate Play': ['lionsgate', 'lionsgateplay'],
    'Discovery+': ['discovery+', 'discovery plus', 'discoveryplus'],
    'Audible': ['audible', 'audible.com', 'audible.in'],
    // Matrimony platforms
    'Shaadi': ['shaadi', 'shaadi.com'],
    'Bharatmatrimony': ['bharatmatrimony', 'bharat matrimony', 'bharatmatrimony.com'],
    'Jeevansathi': ['jeevansathi', 'jeevan sathi', 'jeevansathi.com'],
    'Brahminmatrimony': ['brahminmatrimony', 'brahmin matrimony'],
  };

  /// Matrimony platforms for category detection
  static const Set<String> matrimonyPlatforms = {
    'Shaadi',
    'Bharatmatrimony',
    'Jeevansathi',
    'Brahminmatrimony',
  };

  /// Known pricing for frequency detection (INR)
  static const Map<String, Map<SubscriptionFrequency, List<double>>> knownPricing = {
    'Netflix': {
      SubscriptionFrequency.monthly: [149, 199, 499, 649, 799],
      SubscriptionFrequency.yearly: [1788, 2388, 5988, 7788, 9588],
    },
    'Amazon Prime': {
      SubscriptionFrequency.monthly: [299],
      SubscriptionFrequency.quarterly: [599],
      SubscriptionFrequency.yearly: [1499],
    },
    'Disney+ Hotstar': {
      SubscriptionFrequency.monthly: [149, 299, 499],
      SubscriptionFrequency.yearly: [899, 1499],
    },
    'Zee5': {
      SubscriptionFrequency.monthly: [99, 299],
      SubscriptionFrequency.yearly: [599, 999, 1299],
    },
    'SonyLIV': {
      SubscriptionFrequency.monthly: [299, 699],
      SubscriptionFrequency.yearly: [999, 1499],
    },
    'YouTube Premium': {
      SubscriptionFrequency.monthly: [129, 139, 189],
      SubscriptionFrequency.yearly: [1290, 1390, 1890],
    },
    'Spotify': {
      SubscriptionFrequency.monthly: [119, 149, 179, 199],
      SubscriptionFrequency.yearly: [1189, 1490, 1790],
    },
  };

  /// Regex patterns for parsing different message formats

  // Pattern 1: Mandate/Autopay setup
  // "mandate set for DD-MM-YY, INR AMOUNT will be debited...towards PLATFORM"
  static final RegExp _mandatePattern = RegExp(
    r'mandate\s+(?:set|registered)\s+for\s+(\d{2}[-/]\d{2}[-/]\d{2,4}),?\s*(?:INR|Rs\.?|₹)\s*([\d,]+(?:\.\d{2})?)\s*(?:will\s+be\s+debited|to\s+be\s+debited).*?(?:towards|for)\s+([A-Za-z0-9\s\.\-]+?)(?:\s+for|\s+Ref|,|\.|$)',
    caseSensitive: false,
  );

  // Pattern 2: Debit notification
  // "debited towards PLATFORM for INR AMOUNT on DD-MM-YY"
  static final RegExp _debitTowardsPattern = RegExp(
    r'(?:debited|deducted)\s+(?:towards|for)\s+([A-Za-z0-9\s\.\-]+?)\s+(?:for|of)\s+(?:INR|Rs\.?|₹)\s*([\d,]+(?:\.\d{2})?)\s+on\s+(\d{2}[-/]\d{2}[-/]\d{2,4})',
    caseSensitive: false,
  );

  // Pattern 3: Standard debit
  // "INR AMOUNT debited from a/c...for PLATFORM on DD-MM-YY"
  static final RegExp _standardDebitPattern = RegExp(
    r'(?:INR|Rs\.?|₹)\s*([\d,]+(?:\.\d{2})?)\s+(?:debited|deducted).*?(?:for|towards)\s+([A-Za-z0-9\s\.\-]+?)\s+on\s+(\d{2}[-/]\d{2}[-/]\d{2,4})',
    caseSensitive: false,
  );

  // Pattern 4: Recurring payment
  // "recurring payment of INR AMOUNT to PLATFORM"
  static final RegExp _recurringPattern = RegExp(
    r'recurring\s+payment\s+(?:of\s+)?(?:INR|Rs\.?|₹)\s*([\d,]+(?:\.\d{2})?)\s+(?:to|for|towards)\s+([A-Za-z0-9\s\.\-]+?)(?:\s+on\s+(\d{2}[-/]\d{2}[-/]\d{2,4}))?',
    caseSensitive: false,
  );

  // Pattern 5: Subscription renewal
  // "subscription renewed for PLATFORM, INR AMOUNT debited"
  static final RegExp _renewalPattern = RegExp(
    r'subscription\s+(?:renewed|charged).*?(?:for|to)\s+([A-Za-z0-9\s\.\-]+?).*?(?:INR|Rs\.?|₹)\s*([\d,]+(?:\.\d{2})?)',
    caseSensitive: false,
  );

  // Pattern 6: Credit card spent notification (Axis, HDFC, etc.)
  // "Spent INR 649 ... 07-10-25 ... NETFLIX"
  static final RegExp _spentPattern = RegExp(
    r'Spent\s+(?:INR|Rs\.?|₹)\s*([\d,]+(?:\.\d{2})?)\s+.*?(\d{2}[-/]\d{2}[-/]\d{2,4})\s+\d{2}:\d{2}:\d{2}\s+\w+\s+([A-Z][A-Z0-9\s\.]+?)(?:\s+Avl|\s+Available|\s+Not\s+you)',
    caseSensitive: false,
  );

  // Pattern 7: Autopay reminder/notification
  // "INR 649.00 for NETFLIX will be auto debited via ... by DD-MM-YY"
  static final RegExp _autopayReminderPattern = RegExp(
    r'(?:INR|Rs\.?|₹)\s*([\d,]+(?:\.\d{2})?)\s+for\s+([A-Za-z0-9\s\.\-]+?)\s+will\s+be\s+(?:auto\s+)?debited\s+.*?(?:by|on)\s+(\d{2}[-/]\d{2}[-/]\d{2,4})',
    caseSensitive: false,
  );

  /// Parse all SMS messages and extract subscriptions
  /// If [sinceDate] is provided, only parses messages after that timestamp
  Future<List<ParsedSubscription>> parseSubscriptions({
    int daysToFetch = 365,
    DateTime? sinceDate,
    void Function(int current, int total)? onProgress,
  }) async {
    final messages = await _smsService.readBankSms(
      daysToFetch: daysToFetch,
      sinceDate: sinceDate,
    );
    final subscriptions = <ParsedSubscription>[];
    final processedHashes = <String>{};

    for (var i = 0; i < messages.length; i++) {
      final msg = messages[i];
      onProgress?.call(i + 1, messages.length);

      final parsed = _parseSingleMessage(msg);
      if (parsed != null && !processedHashes.contains(parsed.smsHash)) {
        subscriptions.add(parsed);
        processedHashes.add(parsed.smsHash);
      }
    }

    // Date-interval-based frequency detection (overrides amount heuristic)
    // Group by platform + amount to find recurring payments
    final groups = <String, List<ParsedSubscription>>{};
    for (final sub in subscriptions) {
      final key = '${sub.platform}_${sub.amount.toStringAsFixed(2)}';
      groups.putIfAbsent(key, () => []).add(sub);
    }
    for (final entry in groups.entries) {
      final group = entry.value;
      if (group.length < 2) continue;

      // Sort by date ascending for interval calculation
      group.sort((a, b) => a.paymentDate.compareTo(b.paymentDate));

      // Calculate average interval between consecutive payments
      var totalDays = 0;
      for (var i = 1; i < group.length; i++) {
        totalDays +=
            group[i].paymentDate.difference(group[i - 1].paymentDate).inDays;
      }
      final avgDays = totalDays / (group.length - 1);

      // Map interval to frequency
      SubscriptionFrequency inferredFreq;
      if (avgDays <= 45) {
        inferredFreq = SubscriptionFrequency.monthly;
      } else if (avgDays <= 120) {
        inferredFreq = SubscriptionFrequency.quarterly;
      } else if (avgDays <= 240) {
        inferredFreq = SubscriptionFrequency.halfYearly;
      } else {
        inferredFreq = SubscriptionFrequency.yearly;
      }

      // Override frequency for all items in the group
      for (var i = 0; i < subscriptions.length; i++) {
        if (subscriptions[i].platform == group.first.platform &&
            subscriptions[i].amount == group.first.amount) {
          subscriptions[i] = subscriptions[i].copyWith(frequency: inferredFreq);
        }
      }
    }

    // Sort by payment date (most recent first)
    subscriptions.sort((a, b) => b.paymentDate.compareTo(a.paymentDate));

    // Deduplicate by platform + amount + exact day of month (no buffer)
    final uniqueKey = <String, ParsedSubscription>{};
    for (final sub in subscriptions) {
      final dayOfMonth = sub.paymentDate.day;
      final key = '${sub.platform}_${sub.amount.toStringAsFixed(2)}_$dayOfMonth';
      if (!uniqueKey.containsKey(key)) {
        uniqueKey[key] = sub;
      }
    }

    return uniqueKey.values.toList();
  }

  /// Parse a single SMS message
  ParsedSubscription? _parseSingleMessage(BankSmsMessage msg) {
    final body = msg.body;
    final bankName = _smsService.getBankNameFromAddress(msg.address);

    // Try each pattern
    ParsedSubscription? result;

    result = _tryMandatePattern(body, msg.date, bankName);
    if (result != null) return result;

    result = _tryDebitTowardsPattern(body, msg.date, bankName);
    if (result != null) return result;

    result = _tryStandardDebitPattern(body, msg.date, bankName);
    if (result != null) return result;

    result = _tryRecurringPattern(body, msg.date, bankName);
    if (result != null) return result;

    result = _tryRenewalPattern(body, msg.date, bankName);
    if (result != null) return result;

    result = _trySpentPattern(body, msg.date, bankName);
    if (result != null) return result;

    result = _tryAutopayReminderPattern(body, msg.date, bankName);
    if (result != null) return result;

    return null;
  }

  ParsedSubscription? _tryMandatePattern(
      String body, DateTime msgDate, String? bankName) {
    final match = _mandatePattern.firstMatch(body);
    if (match == null) return null;

    final dateStr = match.group(1)!;
    final amountStr = match.group(2)!;
    final platformRaw = match.group(3)!;

    final platform = _normalizePlatform(platformRaw);
    if (platform == null) return null;

    final amount = _parseAmount(amountStr);
    if (amount == null || amount <= 0) return null;

    final date = _parseDate(dateStr) ?? msgDate;
    final frequency = _detectFrequency(platform, amount);
    final smsHash = _generateHash(body);

    return ParsedSubscription(
      platform: platform,
      amount: amount,
      paymentDate: date,
      frequency: frequency,
      category: _detectCategory(platform),
      bankName: bankName,
      smsHash: smsHash,
    );
  }

  ParsedSubscription? _tryDebitTowardsPattern(
      String body, DateTime msgDate, String? bankName) {
    final match = _debitTowardsPattern.firstMatch(body);
    if (match == null) return null;

    final platformRaw = match.group(1)!;
    final amountStr = match.group(2)!;
    final dateStr = match.group(3)!;

    final platform = _normalizePlatform(platformRaw);
    if (platform == null) return null;

    final amount = _parseAmount(amountStr);
    if (amount == null || amount <= 0) return null;

    final date = _parseDate(dateStr) ?? msgDate;
    final frequency = _detectFrequency(platform, amount);
    final smsHash = _generateHash(body);

    return ParsedSubscription(
      platform: platform,
      amount: amount,
      paymentDate: date,
      frequency: frequency,
      category: _detectCategory(platform),
      bankName: bankName,
      smsHash: smsHash,
    );
  }

  ParsedSubscription? _tryStandardDebitPattern(
      String body, DateTime msgDate, String? bankName) {
    final match = _standardDebitPattern.firstMatch(body);
    if (match == null) return null;

    final amountStr = match.group(1)!;
    final platformRaw = match.group(2)!;
    final dateStr = match.group(3)!;

    final platform = _normalizePlatform(platformRaw);
    if (platform == null) return null;

    final amount = _parseAmount(amountStr);
    if (amount == null || amount <= 0) return null;

    final date = _parseDate(dateStr) ?? msgDate;
    final frequency = _detectFrequency(platform, amount);
    final smsHash = _generateHash(body);

    return ParsedSubscription(
      platform: platform,
      amount: amount,
      paymentDate: date,
      frequency: frequency,
      category: _detectCategory(platform),
      bankName: bankName,
      smsHash: smsHash,
    );
  }

  ParsedSubscription? _tryRecurringPattern(
      String body, DateTime msgDate, String? bankName) {
    final match = _recurringPattern.firstMatch(body);
    if (match == null) return null;

    final amountStr = match.group(1)!;
    final platformRaw = match.group(2)!;
    final dateStr = match.group(3);

    final platform = _normalizePlatform(platformRaw);
    if (platform == null) return null;

    final amount = _parseAmount(amountStr);
    if (amount == null || amount <= 0) return null;

    final date = dateStr != null ? _parseDate(dateStr) ?? msgDate : msgDate;
    final frequency = _detectFrequency(platform, amount);
    final smsHash = _generateHash(body);

    return ParsedSubscription(
      platform: platform,
      amount: amount,
      paymentDate: date,
      frequency: frequency,
      category: _detectCategory(platform),
      bankName: bankName,
      smsHash: smsHash,
    );
  }

  ParsedSubscription? _tryRenewalPattern(
      String body, DateTime msgDate, String? bankName) {
    final match = _renewalPattern.firstMatch(body);
    if (match == null) return null;

    final platformRaw = match.group(1)!;
    final amountStr = match.group(2)!;

    final platform = _normalizePlatform(platformRaw);
    if (platform == null) return null;

    final amount = _parseAmount(amountStr);
    if (amount == null || amount <= 0) return null;

    final frequency = _detectFrequency(platform, amount);
    final smsHash = _generateHash(body);

    return ParsedSubscription(
      platform: platform,
      amount: amount,
      paymentDate: msgDate,
      frequency: frequency,
      category: _detectCategory(platform),
      bankName: bankName,
      smsHash: smsHash,
    );
  }

  ParsedSubscription? _trySpentPattern(
      String body, DateTime msgDate, String? bankName) {
    final match = _spentPattern.firstMatch(body);
    if (match == null) return null;

    final amountStr = match.group(1)!;
    final dateStr = match.group(2)!;
    final platformRaw = match.group(3)!;

    final platform = _normalizePlatform(platformRaw);
    if (platform == null) return null;

    final amount = _parseAmount(amountStr);
    if (amount == null || amount <= 0) return null;

    final date = _parseDate(dateStr) ?? msgDate;
    final frequency = _detectFrequency(platform, amount);
    final smsHash = _generateHash(body);

    return ParsedSubscription(
      platform: platform,
      amount: amount,
      paymentDate: date,
      frequency: frequency,
      category: _detectCategory(platform),
      bankName: bankName,
      smsHash: smsHash,
    );
  }

  ParsedSubscription? _tryAutopayReminderPattern(
      String body, DateTime msgDate, String? bankName) {
    final match = _autopayReminderPattern.firstMatch(body);
    if (match == null) return null;

    final amountStr = match.group(1)!;
    final platformRaw = match.group(2)!;
    final dateStr = match.group(3)!;

    final platform = _normalizePlatform(platformRaw);
    if (platform == null) return null;

    final amount = _parseAmount(amountStr);
    if (amount == null || amount <= 0) return null;

    final date = _parseDate(dateStr) ?? msgDate;
    final frequency = _detectFrequency(platform, amount);
    final smsHash = _generateHash(body);

    return ParsedSubscription(
      platform: platform,
      amount: amount,
      paymentDate: date,
      frequency: frequency,
      category: _detectCategory(platform),
      bankName: bankName,
      smsHash: smsHash,
    );
  }

  /// Normalize platform name from raw text
  String? _normalizePlatform(String raw) {
    final normalized = raw.trim().toLowerCase();

    // Check known aliases first
    for (final entry in platformAliases.entries) {
      for (final alias in entry.value) {
        if (normalized.contains(alias)) {
          return entry.key;
        }
      }
    }

    // If exact match with known platform names (case-insensitive)
    final knownPlatforms = platformAliases.keys.toList();
    for (final platform in knownPlatforms) {
      if (normalized == platform.toLowerCase()) {
        return platform;
      }
    }

    // Accept any platform containing "matrimony" in the name
    if (normalized.contains('matrimony')) {
      final cleaned = raw.trim();
      return cleaned[0].toUpperCase() + cleaned.substring(1).toLowerCase();
    }

    // Return cleaned-up name if it looks like a valid platform (all caps in original)
    final cleaned = raw.trim();
    if (cleaned.toUpperCase() == cleaned && cleaned.length >= 3) {
      // It's all caps like "NETFLIX" - title case it
      return cleaned[0].toUpperCase() + cleaned.substring(1).toLowerCase();
    }

    return null;
  }

  /// Parse amount string to double
  double? _parseAmount(String amountStr) {
    try {
      // Remove commas and parse
      final cleaned = amountStr.replaceAll(',', '').trim();
      return double.parse(cleaned);
    } catch (e) {
      return null;
    }
  }

  /// Parse date string to DateTime
  DateTime? _parseDate(String dateStr) {
    try {
      // Handle DD-MM-YY or DD-MM-YYYY format
      final parts = dateStr.split(RegExp(r'[-/]'));
      if (parts.length != 3) return null;

      final day = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      var year = int.parse(parts[2]);

      // Handle 2-digit year
      if (year < 100) {
        year += 2000;
      }

      return DateTime(year, month, day);
    } catch (e) {
      return null;
    }
  }

  /// Detect subscription category based on platform name
  SubscriptionCategory _detectCategory(String platform) {
    if (matrimonyPlatforms.contains(platform)) {
      return SubscriptionCategory.matrimony;
    }
    if (platform.toLowerCase().contains('matrimony')) {
      return SubscriptionCategory.matrimony;
    }
    return SubscriptionCategory.ott;
  }

  /// Detect subscription frequency based on platform and amount
  SubscriptionFrequency _detectFrequency(String platform, double amount) {
    // Check known pricing first
    final pricing = knownPricing[platform];
    if (pricing != null) {
      for (final entry in pricing.entries) {
        for (final price in entry.value) {
          // Allow 10% tolerance for price matching
          if ((amount - price).abs() <= price * 0.1) {
            return entry.key;
          }
        }
      }
    }

    // Heuristic: amount < 800 = monthly, else yearly
    if (amount < 800) {
      return SubscriptionFrequency.monthly;
    } else if (amount < 2000) {
      return SubscriptionFrequency.quarterly;
    } else {
      return SubscriptionFrequency.yearly;
    }
  }

  /// Generate SHA-256 hash of SMS body for deduplication
  String _generateHash(String body) {
    final bytes = utf8.encode(body);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
