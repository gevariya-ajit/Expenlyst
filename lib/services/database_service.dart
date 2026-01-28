import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';
import '../models/expense.dart';

class DatabaseService {
  static Database? _database;
  static const _uuid = Uuid();

  /// Helper to add column only if it doesn't exist
  Future<void> _addColumnIfNotExists(
    Database db,
    String table,
    String column,
    String type,
  ) async {
    final result = await db.rawQuery('PRAGMA table_info($table)');
    final columnExists = result.any((row) => row['name'] == column);
    if (!columnExists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    }
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'expenlyst.db');

    return await openDatabase(
      path,
      version: 5,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE expenses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            uuid TEXT,
            label TEXT NOT NULL,
            datetime TEXT NOT NULL,
            category TEXT NOT NULL,
            amount REAL NOT NULL,
            tickerSinceAddUpdate TEXT DEFAULT '0',
            isDeleted INTEGER DEFAULT 0,
            deviceId TEXT,
            archivedAt TEXT
          )
        ''');
        // Create indexes
        await db.execute('CREATE INDEX idx_expenses_datetime ON expenses(datetime)');
        await db.execute('CREATE INDEX idx_expenses_ticker ON expenses(tickerSinceAddUpdate)');
        await db.execute('CREATE UNIQUE INDEX idx_expenses_uuid ON expenses(uuid)');
        await db.execute('CREATE INDEX idx_expenses_archived ON expenses(archivedAt)');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Add index for faster datetime queries
          await db.execute('CREATE INDEX IF NOT EXISTS idx_expenses_datetime ON expenses(datetime)');
        }
        if (oldVersion < 3) {
          // Add tickerSinceAddUpdate column for sync tracking
          await _addColumnIfNotExists(db, 'expenses', 'tickerSinceAddUpdate', "TEXT DEFAULT '0'");
          await db.execute('CREATE INDEX IF NOT EXISTS idx_expenses_ticker ON expenses(tickerSinceAddUpdate)');
          // Set default '0' for existing records
          await db.execute("UPDATE expenses SET tickerSinceAddUpdate = '0' WHERE tickerSinceAddUpdate IS NULL");
        }
        if (oldVersion < 4) {
          // Add sync-related columns
          await _addColumnIfNotExists(db, 'expenses', 'uuid', 'TEXT');
          await _addColumnIfNotExists(db, 'expenses', 'isDeleted', 'INTEGER DEFAULT 0');
          await _addColumnIfNotExists(db, 'expenses', 'deviceId', 'TEXT');
          // Generate UUIDs for existing expenses that don't have one
          final existing = await db.query('expenses', columns: ['id', 'uuid']);
          for (final row in existing) {
            if (row['uuid'] == null) {
              final id = row['id'] as int;
              await db.update(
                'expenses',
                {'uuid': _uuid.v4()},
                where: 'id = ?',
                whereArgs: [id],
              );
            }
          }
          await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_expenses_uuid ON expenses(uuid)');
        }
        if (oldVersion < 5) {
          // Add archivedAt column for archive feature
          await _addColumnIfNotExists(db, 'expenses', 'archivedAt', 'TEXT');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_expenses_archived ON expenses(archivedAt)');
        }
      },
    );
  }

  Future<int> insertExpense(Expense expense, {String? deviceId}) async {
    final db = await database;
    final map = expense.toMap();
    map['tickerSinceAddUpdate'] = DateTime.now().toIso8601String();
    map['uuid'] = expense.uuid ?? _uuid.v4();
    map['deviceId'] = deviceId ?? expense.deviceId;
    return await db.insert('expenses', map);
  }

  Future<List<Expense>> getTodayExpenses() async {
    return getExpensesForDate(DateTime.now());
  }

  Future<List<Expense>> getExpensesForDate(DateTime date) async {
    final db = await database;
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final maps = await db.query(
      'expenses',
      where: 'datetime >= ? AND datetime < ? AND isDeleted = 0 AND archivedAt IS NULL',
      whereArgs: [startOfDay.toIso8601String(), endOfDay.toIso8601String()],
      orderBy: 'datetime DESC',
    );

    return maps.map((map) => Expense.fromMap(map)).toList();
  }

  Future<List<Expense>> getWeekExpenses() async {
    return getWeekExpensesForDate(DateTime.now());
  }

  Future<List<Expense>> getWeekExpensesForDate(DateTime date) async {
    final db = await database;
    final startOfWeek = date.subtract(Duration(days: date.weekday - 1));
    final startOfWeekDay = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
    final endOfWeek = startOfWeekDay.add(const Duration(days: 7));

    final maps = await db.query(
      'expenses',
      where: 'datetime >= ? AND datetime < ? AND isDeleted = 0 AND archivedAt IS NULL',
      whereArgs: [startOfWeekDay.toIso8601String(), endOfWeek.toIso8601String()],
    );

    return maps.map((map) => Expense.fromMap(map)).toList();
  }

  Future<List<Expense>> getMonthExpenses() async {
    return getMonthExpensesForDate(DateTime.now());
  }

  Future<List<Expense>> getMonthExpensesForDate(DateTime date) async {
    final db = await database;
    final startOfMonth = DateTime(date.year, date.month, 1);
    final endOfMonth = DateTime(date.year, date.month + 1, 1);

    final maps = await db.query(
      'expenses',
      where: 'datetime >= ? AND datetime < ? AND isDeleted = 0 AND archivedAt IS NULL',
      whereArgs: [startOfMonth.toIso8601String(), endOfMonth.toIso8601String()],
    );

    return maps.map((map) => Expense.fromMap(map)).toList();
  }

  Future<int> deleteExpense(int id) async {
    final db = await database;
    return await db.delete(
      'expenses',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Soft delete an expense (mark as deleted, used for sync)
  Future<int> softDeleteExpense(int id) async {
    final db = await database;
    return await db.update(
      'expenses',
      {
        'isDeleted': 1,
        'tickerSinceAddUpdate': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updateExpense(Expense expense) async {
    final db = await database;
    final map = expense.toMap();
    map['tickerSinceAddUpdate'] = DateTime.now().toIso8601String();
    return await db.update(
      'expenses',
      map,
      where: 'id = ?',
      whereArgs: [expense.id],
    );
  }

  Future<List<Expense>> getAllExpenses() async {
    final db = await database;
    final maps = await db.query(
      'expenses',
      where: 'isDeleted = 0 AND archivedAt IS NULL',
      orderBy: 'datetime DESC',
    );
    return maps.map((map) => Expense.fromMap(map)).toList();
  }

  Future<String?> getCategoryByLabel(String label) async {
    final db = await database;
    final maps = await db.query(
      'expenses',
      columns: ['category'],
      where: 'LOWER(label) = ? AND isDeleted = 0 AND archivedAt IS NULL',
      whereArgs: [label.toLowerCase()],
      orderBy: 'datetime DESC',
      limit: 1,
    );

    if (maps.isNotEmpty) {
      return maps.first['category'] as String;
    }
    return null;
  }

  /// Get all expenses modified since a given timestamp (for sync)
  Future<List<Expense>> getExpensesSince(DateTime since) async {
    final db = await database;
    final maps = await db.query(
      'expenses',
      where: 'tickerSinceAddUpdate > ?',
      whereArgs: [since.toIso8601String()],
      orderBy: 'tickerSinceAddUpdate ASC',
    );
    return maps.map((map) => Expense.fromMap(map)).toList();
  }

  /// Get expense by UUID (for sync)
  Future<Expense?> getExpenseByUuid(String uuid) async {
    final db = await database;
    final maps = await db.query(
      'expenses',
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return Expense.fromMap(maps.first);
    }
    return null;
  }

  /// Get all expenses including deleted ones (for sync)
  Future<List<Expense>> getAllExpensesForSync() async {
    final db = await database;
    final maps = await db.query(
      'expenses',
      orderBy: 'tickerSinceAddUpdate ASC',
    );
    return maps.map((map) => Expense.fromMap(map)).toList();
  }

  /// Clear all expenses (for logout wipe)
  Future<void> clearAllExpenses() async {
    final db = await database;
    await db.delete('expenses');
  }

  /// Insert or update expense from sync (used during download sync)
  Future<void> upsertFromSync(Expense expense) async {
    final db = await database;
    if (expense.uuid == null) return;

    final existing = await getExpenseByUuid(expense.uuid!);
    if (existing == null) {
      // Insert new expense
      final map = expense.toMap();
      map.remove('id'); // Let SQLite auto-generate id
      await db.insert('expenses', map);
    } else {
      // Update existing expense
      final map = expense.toMap();
      map.remove('id');
      await db.update(
        'expenses',
        map,
        where: 'uuid = ?',
        whereArgs: [expense.uuid],
      );
    }
  }

  // Archive methods

  /// Archive an expense
  Future<int> archiveExpense(int id) async {
    final db = await database;
    return await db.update(
      'expenses',
      {
        'archivedAt': DateTime.now().toIso8601String(),
        'tickerSinceAddUpdate': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Restore an expense from archive
  Future<int> restoreExpense(int id) async {
    final db = await database;
    return await db.update(
      'expenses',
      {
        'archivedAt': null,
        'tickerSinceAddUpdate': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Get all archived expenses (within last 30 days)
  Future<List<Expense>> getArchivedExpenses() async {
    final db = await database;
    final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));

    final maps = await db.query(
      'expenses',
      where: 'archivedAt IS NOT NULL AND archivedAt >= ? AND isDeleted = 0',
      whereArgs: [thirtyDaysAgo.toIso8601String()],
      orderBy: 'archivedAt DESC',
    );
    return maps.map((map) => Expense.fromMap(map)).toList();
  }

  /// Permanently delete an archived expense
  Future<int> permanentlyDeleteExpense(int id) async {
    final db = await database;
    return await db.delete(
      'expenses',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Restore all archived expenses
  Future<int> restoreAllArchivedExpenses() async {
    final db = await database;
    final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));

    return await db.update(
      'expenses',
      {
        'archivedAt': null,
        'tickerSinceAddUpdate': DateTime.now().toIso8601String(),
      },
      where: 'archivedAt IS NOT NULL AND archivedAt >= ? AND isDeleted = 0',
      whereArgs: [thirtyDaysAgo.toIso8601String()],
    );
  }

  /// Permanently delete all archived expenses
  Future<int> deleteAllArchivedExpenses() async {
    final db = await database;
    final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));

    return await db.delete(
      'expenses',
      where: 'archivedAt IS NOT NULL AND archivedAt >= ? AND isDeleted = 0',
      whereArgs: [thirtyDaysAgo.toIso8601String()],
    );
  }

  /// Clean up old archived expenses (older than 30 days)
  Future<int> cleanupOldArchivedExpenses() async {
    final db = await database;
    final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));

    return await db.delete(
      'expenses',
      where: 'archivedAt IS NOT NULL AND archivedAt < ?',
      whereArgs: [thirtyDaysAgo.toIso8601String()],
    );
  }

  /// Get recent unique labels for smart label matching
  Future<List<String>> getRecentLabels({int limit = 500}) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT DISTINCT label FROM expenses
      WHERE isDeleted = 0 AND archivedAt IS NULL
      ORDER BY datetime DESC
      LIMIT ?
    ''', [limit]);
    return maps.map((map) => map['label'] as String).toList();
  }
}
