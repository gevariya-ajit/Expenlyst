class Expense {
  final int? id;
  final String? uuid;
  final String label;
  final DateTime datetime;
  final String category;
  final double amount;
  final DateTime? tickerSinceAddUpdate;
  final bool isDeleted;
  final String? deviceId;
  final DateTime? archivedAt;

  Expense({
    this.id,
    this.uuid,
    required this.label,
    required this.datetime,
    required this.category,
    required this.amount,
    this.tickerSinceAddUpdate,
    this.isDeleted = false,
    this.deviceId,
    this.archivedAt,
  });

  bool get isArchived => archivedAt != null;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uuid': uuid,
      'label': label,
      'datetime': datetime.toIso8601String(),
      'category': category,
      'amount': amount,
      'tickerSinceAddUpdate': tickerSinceAddUpdate?.toIso8601String(),
      'isDeleted': isDeleted ? 1 : 0,
      'deviceId': deviceId,
      'archivedAt': archivedAt?.toIso8601String(),
    };
  }

  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      id: map['id'] as int?,
      uuid: map['uuid'] as String?,
      label: map['label'] as String,
      datetime: DateTime.parse(map['datetime'] as String),
      category: map['category'] as String,
      amount: (map['amount'] as num).toDouble(),
      tickerSinceAddUpdate: map['tickerSinceAddUpdate'] != null &&
              map['tickerSinceAddUpdate'] != '0'
          ? DateTime.parse(map['tickerSinceAddUpdate'] as String)
          : null,
      isDeleted: map['isDeleted'] == 1 || map['isDeleted'] == true,
      deviceId: map['deviceId'] as String?,
      archivedAt: map['archivedAt'] != null
          ? DateTime.tryParse(map['archivedAt'] as String)
          : null,
    );
  }

  /// Convert to a list for Google Sheets row
  List<Object> toSheetRow() {
    return [
      uuid ?? '',
      label,
      datetime.toIso8601String(),
      category,
      amount.toString(),
      tickerSinceAddUpdate?.toIso8601String() ?? '',
      isDeleted ? 'TRUE' : 'FALSE',
      deviceId ?? '',
      archivedAt?.toIso8601String() ?? '',
    ];
  }

  /// Create from Google Sheets row
  factory Expense.fromSheetRow(List<Object?> row) {
    return Expense(
      uuid: row[0]?.toString(),
      label: row[1]?.toString() ?? '',
      datetime: DateTime.tryParse(row[2]?.toString() ?? '') ?? DateTime.now(),
      category: row[3]?.toString() ?? 'Miscellaneous',
      amount: double.tryParse(row[4]?.toString() ?? '0') ?? 0.0,
      tickerSinceAddUpdate: row.length > 5 && row[5] != null && row[5].toString().isNotEmpty
          ? DateTime.tryParse(row[5].toString())
          : null,
      isDeleted: row.length > 6 && row[6]?.toString().toUpperCase() == 'TRUE',
      deviceId: row.length > 7 ? row[7]?.toString() : null,
      archivedAt: row.length > 8 && row[8] != null && row[8].toString().isNotEmpty
          ? DateTime.tryParse(row[8].toString())
          : null,
    );
  }

  Expense copyWith({
    int? id,
    String? uuid,
    String? label,
    DateTime? datetime,
    String? category,
    double? amount,
    DateTime? tickerSinceAddUpdate,
    bool? isDeleted,
    String? deviceId,
    DateTime? archivedAt,
    bool clearArchivedAt = false,
  }) {
    return Expense(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      label: label ?? this.label,
      datetime: datetime ?? this.datetime,
      category: category ?? this.category,
      amount: amount ?? this.amount,
      tickerSinceAddUpdate: tickerSinceAddUpdate ?? this.tickerSinceAddUpdate,
      isDeleted: isDeleted ?? this.isDeleted,
      deviceId: deviceId ?? this.deviceId,
      archivedAt: clearArchivedAt ? null : (archivedAt ?? this.archivedAt),
    );
  }
}
