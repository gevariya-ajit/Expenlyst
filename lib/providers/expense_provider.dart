import 'package:flutter/foundation.dart';
import '../models/expense.dart';
import '../services/database_service.dart';

class ExpenseProvider with ChangeNotifier {
  final DatabaseService _databaseService = DatabaseService();

  /// Callback to trigger auto sync after data changes
  VoidCallback? onDataChanged;

  List<Expense> _selectedDateExpenses = [];
  List<Expense> _weekExpenses = [];
  List<Expense> _monthExpenses = [];
  bool _isLoading = false;
  DateTime _selectedDate = DateTime.now();

  List<Expense> get selectedDateExpenses => _selectedDateExpenses;
  List<Expense> get weekExpenses => _weekExpenses;
  List<Expense> get monthExpenses => _monthExpenses;
  bool get isLoading => _isLoading;
  DateTime get selectedDate => _selectedDate;

  bool get isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  double get selectedDateTotal {
    return _selectedDateExpenses.fold(0.0, (sum, expense) => sum + expense.amount);
  }

  double get weeklyTotal {
    return _weekExpenses.fold(0.0, (sum, expense) => sum + expense.amount);
  }

  double get monthlyTotal {
    return _monthExpenses.fold(0.0, (sum, expense) => sum + expense.amount);
  }

  double get weeklyAverage {
    if (_weekExpenses.isEmpty) return 0.0;
    // Calculate days from start of week (Sunday) to selected date
    final now = DateTime.now();
    final effectiveDate = _selectedDate.isAfter(now) ? now : _selectedDate;
    // Sun=1, Mon=2, ..., Sat=7 (days into the Sunday-start week)
    final daysIntoWeek = (effectiveDate.weekday % 7) + 1;
    final total = _weekExpenses.fold(0.0, (sum, expense) => sum + expense.amount);
    return total / daysIntoWeek;
  }

  double get monthlyAverage {
    if (_monthExpenses.isEmpty) return 0.0;
    // Calculate days from start of month to selected date (or today if selected date is in future)
    final now = DateTime.now();
    final effectiveDate = _selectedDate.isAfter(now) ? now : _selectedDate;
    final daysIntoMonth = effectiveDate.day;
    final total = _monthExpenses.fold(0.0, (sum, expense) => sum + expense.amount);
    return total / daysIntoMonth;
  }

  Future<void> setSelectedDate(DateTime date) async {
    _selectedDate = date;
    await loadExpenses();
  }

  Future<void> loadExpenses() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Run all queries in parallel for better performance
      final results = await Future.wait([
        _databaseService.getExpensesForDate(_selectedDate),
        _databaseService.getWeekExpensesForDate(_selectedDate),
        _databaseService.getMonthExpensesForDate(_selectedDate),
      ]);
      _selectedDateExpenses = results[0];
      _weekExpenses = results[1];
      _monthExpenses = results[2];
    } catch (e) {
      debugPrint('Error loading expenses: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> addExpense(Expense expense) async {
    try {
      final id = await _databaseService.insertExpense(expense);
      final newExpense = expense.copyWith(id: id);

      // Add to selected date's list if it matches
      final startOfDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      if (expense.datetime.isAfter(startOfDay) && expense.datetime.isBefore(endOfDay)) {
        _selectedDateExpenses.insert(0, newExpense);
      }

      // Reload all expenses to update stats
      await loadExpenses();

      // Trigger auto sync
      onDataChanged?.call();
    } catch (e) {
      debugPrint('Error adding expense: $e');
    }
  }

  Future<void> deleteExpense(int id) async {
    try {
      await _databaseService.softDeleteExpense(id);
      await loadExpenses();

      // Trigger auto sync
      onDataChanged?.call();
    } catch (e) {
      debugPrint('Error deleting expense: $e');
    }
  }

  Future<void> updateExpense(Expense expense) async {
    try {
      await _databaseService.updateExpense(expense);
      await loadExpenses();

      // Trigger auto sync
      onDataChanged?.call();
    } catch (e) {
      debugPrint('Error updating expense: $e');
    }
  }

  Future<String?> getCategoryByLabel(String label) async {
    try {
      return await _databaseService.getCategoryByLabel(label);
    } catch (e) {
      debugPrint('Error getting category by label: $e');
      return null;
    }
  }

  Future<List<Expense>> getAllExpenses() async {
    try {
      return await _databaseService.getAllExpenses();
    } catch (e) {
      debugPrint('Error getting all expenses: $e');
      return [];
    }
  }

  /// Clear all data (for logout wipe)
  Future<void> clearAllData() async {
    try {
      await _databaseService.clearAllExpenses();
      _selectedDateExpenses = [];
      _weekExpenses = [];
      _monthExpenses = [];
      notifyListeners();
    } catch (e) {
      debugPrint('Error clearing all data: $e');
    }
  }

  /// Soft delete expense (marks as deleted for sync)
  Future<void> softDeleteExpense(int id) async {
    try {
      await _databaseService.softDeleteExpense(id);
      await loadExpenses();
    } catch (e) {
      debugPrint('Error soft deleting expense: $e');
    }
  }

  // Archive methods

  /// Archive an expense
  Future<void> archiveExpense(int id) async {
    try {
      await _databaseService.archiveExpense(id);
      await loadExpenses();
      onDataChanged?.call();
    } catch (e) {
      debugPrint('Error archiving expense: $e');
    }
  }

  /// Restore an expense from archive
  Future<void> restoreExpense(int id) async {
    try {
      await _databaseService.restoreExpense(id);
      await loadExpenses();
      onDataChanged?.call();
    } catch (e) {
      debugPrint('Error restoring expense: $e');
    }
  }

  /// Get all archived expenses
  Future<List<Expense>> getArchivedExpenses() async {
    try {
      // Clean up old archived expenses first
      await _databaseService.cleanupOldArchivedExpenses();
      return await _databaseService.getArchivedExpenses();
    } catch (e) {
      debugPrint('Error getting archived expenses: $e');
      return [];
    }
  }

  /// Permanently delete an archived expense
  Future<void> permanentlyDeleteExpense(int id) async {
    try {
      await _databaseService.permanentlyDeleteExpense(id);
    } catch (e) {
      debugPrint('Error permanently deleting expense: $e');
    }
  }

  /// Restore all archived expenses
  Future<int> restoreAllArchivedExpenses() async {
    try {
      final count = await _databaseService.restoreAllArchivedExpenses();
      await loadExpenses();
      onDataChanged?.call();
      return count;
    } catch (e) {
      debugPrint('Error restoring all archived expenses: $e');
      return 0;
    }
  }

  /// Delete all archived expenses permanently
  Future<int> deleteAllArchivedExpenses() async {
    try {
      return await _databaseService.deleteAllArchivedExpenses();
    } catch (e) {
      debugPrint('Error deleting all archived expenses: $e');
      return 0;
    }
  }
}
