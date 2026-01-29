import 'package:uuid/uuid.dart';

enum SubscriptionFrequency {
  monthly,
  quarterly,
  halfYearly,
  yearly;

  String get displayName {
    switch (this) {
      case SubscriptionFrequency.monthly:
        return 'Monthly';
      case SubscriptionFrequency.quarterly:
        return 'Quarterly';
      case SubscriptionFrequency.halfYearly:
        return 'Half Yearly';
      case SubscriptionFrequency.yearly:
        return 'Yearly';
    }
  }

  String get shortName {
    switch (this) {
      case SubscriptionFrequency.monthly:
        return '/mo';
      case SubscriptionFrequency.quarterly:
        return '/qtr';
      case SubscriptionFrequency.halfYearly:
        return '/6mo';
      case SubscriptionFrequency.yearly:
        return '/yr';
    }
  }

  int get monthsPerCycle {
    switch (this) {
      case SubscriptionFrequency.monthly:
        return 1;
      case SubscriptionFrequency.quarterly:
        return 3;
      case SubscriptionFrequency.halfYearly:
        return 6;
      case SubscriptionFrequency.yearly:
        return 12;
    }
  }
}

enum SubscriptionCategory {
  ott,
  matrimony,
  mobileBill,
  other;

  String get displayName {
    switch (this) {
      case SubscriptionCategory.ott:
        return 'OTT';
      case SubscriptionCategory.matrimony:
        return 'Matrimony';
      case SubscriptionCategory.mobileBill:
        return 'Mobile Bill';
      case SubscriptionCategory.other:
        return 'Other';
    }
  }
}

class Subscription {
  final int? id;
  final String uuid;
  final String platform;
  final SubscriptionCategory category;
  final double amount;
  final SubscriptionFrequency frequency;
  final DateTime lastPaymentDate;
  final DateTime? nextPaymentDate;
  final String? bankName;
  final String? smsHash;
  final bool isActive;
  final bool isDeleted;
  final DateTime createdAt;

  Subscription({
    this.id,
    String? uuid,
    required this.platform,
    required this.category,
    required this.amount,
    required this.frequency,
    required this.lastPaymentDate,
    this.nextPaymentDate,
    this.bankName,
    this.smsHash,
    this.isActive = true,
    this.isDeleted = false,
    DateTime? createdAt,
  })  : uuid = uuid ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  /// Calculate monthly cost for comparison
  double get monthlyCost {
    return amount / frequency.monthsPerCycle;
  }

  /// Calculate next payment date based on frequency
  DateTime calculateNextPaymentDate() {
    return DateTime(
      lastPaymentDate.year,
      lastPaymentDate.month + frequency.monthsPerCycle,
      lastPaymentDate.day,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uuid': uuid,
      'platform': platform,
      'category': category.name,
      'amount': amount,
      'frequency': frequency.name,
      'lastPaymentDate': lastPaymentDate.toIso8601String(),
      'nextPaymentDate': nextPaymentDate?.toIso8601String(),
      'bankName': bankName,
      'smsHash': smsHash,
      'isActive': isActive ? 1 : 0,
      'isDeleted': isDeleted ? 1 : 0,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Subscription.fromMap(Map<String, dynamic> map) {
    return Subscription(
      id: map['id'] as int?,
      uuid: map['uuid'] as String,
      platform: map['platform'] as String,
      category: SubscriptionCategory.values.firstWhere(
        (e) => e.name == map['category'],
        orElse: () => SubscriptionCategory.other,
      ),
      amount: (map['amount'] as num).toDouble(),
      frequency: SubscriptionFrequency.values.firstWhere(
        (e) => e.name == map['frequency'],
        orElse: () => SubscriptionFrequency.monthly,
      ),
      lastPaymentDate: DateTime.parse(map['lastPaymentDate'] as String),
      nextPaymentDate: map['nextPaymentDate'] != null
          ? DateTime.tryParse(map['nextPaymentDate'] as String)
          : null,
      bankName: map['bankName'] as String?,
      smsHash: map['smsHash'] as String?,
      isActive: map['isActive'] == 1 || map['isActive'] == true,
      isDeleted: map['isDeleted'] == 1 || map['isDeleted'] == true,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }

  Subscription copyWith({
    int? id,
    String? uuid,
    String? platform,
    SubscriptionCategory? category,
    double? amount,
    SubscriptionFrequency? frequency,
    DateTime? lastPaymentDate,
    DateTime? nextPaymentDate,
    String? bankName,
    String? smsHash,
    bool? isActive,
    bool? isDeleted,
    DateTime? createdAt,
    bool clearNextPaymentDate = false,
  }) {
    return Subscription(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      platform: platform ?? this.platform,
      category: category ?? this.category,
      amount: amount ?? this.amount,
      frequency: frequency ?? this.frequency,
      lastPaymentDate: lastPaymentDate ?? this.lastPaymentDate,
      nextPaymentDate:
          clearNextPaymentDate ? null : (nextPaymentDate ?? this.nextPaymentDate),
      bankName: bankName ?? this.bankName,
      smsHash: smsHash ?? this.smsHash,
      isActive: isActive ?? this.isActive,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() {
    return 'Subscription(platform: $platform, amount: $amount, frequency: ${frequency.displayName})';
  }
}
