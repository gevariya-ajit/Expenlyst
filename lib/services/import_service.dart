import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../models/expense.dart';

class ImportService {
  /// Pick a CSV file and return parsed expenses
  Future<ImportResult> importFromCsv() async {
    try {
      // Pick CSV file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result == null || result.files.isEmpty) {
        return ImportResult(
          success: false,
          message: 'No file selected',
          expenses: [],
        );
      }

      final file = File(result.files.single.path!);
      final content = await file.readAsString();

      // Parse CSV
      final lines = content.split('\n');
      if (lines.isEmpty) {
        return ImportResult(
          success: false,
          message: 'File is empty',
          expenses: [],
        );
      }

      final expenses = <Expense>[];
      final errors = <String>[];

      // Skip header if present (check if first line contains 'date' or 'label')
      int startIndex = 0;
      if (lines.first.toLowerCase().contains('date') ||
          lines.first.toLowerCase().contains('label')) {
        startIndex = 1;
      }

      for (int i = startIndex; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;

        try {
          final expense = _parseCsvLine(line, i + 1);
          if (expense != null) {
            expenses.add(expense);
          }
        } catch (e) {
          errors.add('Line ${i + 1}: $e');
        }
      }

      if (expenses.isEmpty && errors.isNotEmpty) {
        return ImportResult(
          success: false,
          message: 'Failed to parse CSV: ${errors.first}',
          expenses: [],
        );
      }

      return ImportResult(
        success: true,
        message: 'Imported ${expenses.length} expenses${errors.isNotEmpty ? ' (${errors.length} errors)' : ''}',
        expenses: expenses,
        errors: errors,
      );
    } catch (e) {
      return ImportResult(
        success: false,
        message: 'Error reading file: $e',
        expenses: [],
      );
    }
  }

  Expense? _parseCsvLine(String line, int lineNumber) {
    // Handle both comma and semicolon as delimiters
    final delimiter = line.contains(';') ? ';' : ',';
    final parts = _parseCsvFields(line, delimiter);

    if (parts.length < 4) {
      throw 'Expected 4 columns (date, label, amount, category), got ${parts.length}';
    }

    // Parse date (dd-mm-yy format)
    final dateStr = parts[0].trim();
    final date = _parseDate(dateStr);
    if (date == null) {
      throw 'Invalid date format: $dateStr (expected dd-mm-yy)';
    }

    // Parse label
    final label = parts[1].trim();
    if (label.isEmpty) {
      throw 'Label cannot be empty';
    }

    // Parse amount
    final amountStr = parts[2].trim().replaceAll(',', '');
    final amount = double.tryParse(amountStr);
    if (amount == null) {
      throw 'Invalid amount: ${parts[2]}';
    }

    // Parse category
    final category = parts[3].trim();

    return Expense(
      label: label,
      datetime: date,
      category: category.isEmpty ? 'Miscellaneous' : category,
      amount: amount,
    );
  }

  List<String> _parseCsvFields(String line, String delimiter) {
    final fields = <String>[];
    var current = StringBuffer();
    var inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];

      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == delimiter && !inQuotes) {
        fields.add(current.toString());
        current = StringBuffer();
      } else {
        current.write(char);
      }
    }
    fields.add(current.toString());

    return fields;
  }

  DateTime? _parseDate(String dateStr) {
    // Try dd-mm-yy format
    final parts = dateStr.split(RegExp(r'[-/.]'));
    if (parts.length == 3) {
      try {
        final day = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        var year = int.parse(parts[2]);

        // Handle 2-digit year
        if (year < 100) {
          year += year > 50 ? 1900 : 2000;
        }

        return DateTime(year, month, day, 12, 0); // Set time to noon
      } catch (e) {
        return null;
      }
    }
    return null;
  }
}

class ImportResult {
  final bool success;
  final String message;
  final List<Expense> expenses;
  final List<String> errors;

  ImportResult({
    required this.success,
    required this.message,
    required this.expenses,
    this.errors = const [],
  });
}
