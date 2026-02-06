import 'package:flutter/foundation.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import '../models/expense.dart';
import '../models/subscription.dart';

class SheetInfo {
  final String id;
  final String name;
  final DateTime? modifiedTime;

  SheetInfo({
    required this.id,
    required this.name,
    this.modifiedTime,
  });
}

class SheetsService {
  static const String _sheetName = 'Expenses';
  static const List<String> _headerRow = [
    'uuid',
    'label',
    'datetime',
    'category',
    'amount',
    'tickerSinceAddUpdate',
    'isDeleted',
    'deviceId',
    'archivedAt',
  ];

  // Subscriptions sheet
  static const String _subscriptionsSheetName = 'Subscriptions';
  static const List<String> _subscriptionsHeaderRow = [
    'uuid',
    'platform',
    'category',
    'amount',
    'frequency',
    'lastPaymentDate',
    'nextPaymentDate',
    'bankName',
    'isActive',
    'isDeleted',
    'createdAt',
  ];

  /// Create a new Expenlyst spreadsheet
  Future<String?> createSpreadsheet(http.Client client, {String name = 'Expenlyst Expenses'}) async {
    try {
      final sheetsApi = sheets.SheetsApi(client);

      final spreadsheet = sheets.Spreadsheet(
        properties: sheets.SpreadsheetProperties(title: name),
        sheets: [
          sheets.Sheet(
            properties: sheets.SheetProperties(
              title: _sheetName,
              gridProperties: sheets.GridProperties(
                frozenRowCount: 1,
              ),
            ),
          ),
        ],
      );

      final created = await sheetsApi.spreadsheets.create(spreadsheet);
      final spreadsheetId = created.spreadsheetId;

      if (spreadsheetId != null) {
        // Add header row
        await sheetsApi.spreadsheets.values.update(
          sheets.ValueRange(values: [_headerRow]),
          spreadsheetId,
          '$_sheetName!A1:I1',
          valueInputOption: 'RAW',
        );
      }

      return spreadsheetId;
    } catch (e) {
      debugPrint('Error creating spreadsheet: $e');
      return null;
    }
  }

  /// List all Expenlyst spreadsheets for the user
  Future<List<SheetInfo>> listExpenlystSheets(http.Client client) async {
    try {
      final driveApi = drive.DriveApi(client);

      final fileList = await driveApi.files.list(
        q: "mimeType='application/vnd.google-apps.spreadsheet' and name contains 'Expenlyst' and trashed=false",
        spaces: 'drive',
        $fields: 'files(id, name, modifiedTime)',
        orderBy: 'modifiedTime desc',
      );

      return fileList.files?.map((file) {
            return SheetInfo(
              id: file.id ?? '',
              name: file.name ?? 'Unnamed',
              modifiedTime: file.modifiedTime,
            );
          }).toList() ??
          [];
    } catch (e) {
      debugPrint('Error listing sheets: $e');
      return [];
    }
  }

  /// Read all expenses from a spreadsheet
  Future<List<Expense>> readAllExpenses(http.Client client, String spreadsheetId) async {
    try {
      final sheetsApi = sheets.SheetsApi(client);

      // Ensure the sheet exists first
      await _ensureSheetExists(sheetsApi, spreadsheetId);

      final response = await sheetsApi.spreadsheets.values.get(
        spreadsheetId,
        '$_sheetName!A2:I',
      );

      final values = response.values;
      if (values == null || values.isEmpty) {
        return [];
      }

      return values.map((row) => Expense.fromSheetRow(row)).toList();
    } catch (e) {
      debugPrint('Error reading expenses from sheet: $e');
      return [];
    }
  }

  /// Ensure the Expenses sheet exists with headers
  Future<bool> _ensureSheetExists(sheets.SheetsApi sheetsApi, String spreadsheetId) async {
    try {
      final spreadsheet = await sheetsApi.spreadsheets.get(spreadsheetId);
      final sheetExists = spreadsheet.sheets?.any(
        (s) => s.properties?.title == _sheetName,
      ) ?? false;

      if (!sheetExists) {
        // Create the Expenses sheet
        await sheetsApi.spreadsheets.batchUpdate(
          sheets.BatchUpdateSpreadsheetRequest(
            requests: [
              sheets.Request(
                addSheet: sheets.AddSheetRequest(
                  properties: sheets.SheetProperties(
                    title: _sheetName,
                    gridProperties: sheets.GridProperties(frozenRowCount: 1),
                  ),
                ),
              ),
            ],
          ),
          spreadsheetId,
        );

        // Add header row
        await sheetsApi.spreadsheets.values.update(
          sheets.ValueRange(values: [_headerRow]),
          spreadsheetId,
          '$_sheetName!A1:I1',
          valueInputOption: 'RAW',
        );
      }
      return true;
    } catch (e) {
      debugPrint('Error ensuring sheet exists: $e');
      return false;
    }
  }

  /// Write expenses to spreadsheet (append or update)
  Future<bool> writeExpenses(
    http.Client client,
    String spreadsheetId,
    List<Expense> expenses,
  ) async {
    if (expenses.isEmpty) return true;

    try {
      final sheetsApi = sheets.SheetsApi(client);

      // Ensure the sheet exists
      final sheetReady = await _ensureSheetExists(sheetsApi, spreadsheetId);
      if (!sheetReady) {
        debugPrint('Failed to ensure sheet exists');
        return false;
      }

      // First, get all existing rows to find UUIDs
      sheets.ValueRange? existingData;
      try {
        existingData = await sheetsApi.spreadsheets.values.get(
          spreadsheetId,
          '$_sheetName!A2:I',
        );
      } catch (e) {
        debugPrint('No existing data found (this is OK for new sheets): $e');
        // Sheet might be empty, continue with empty data
      }

      final existingRows = existingData?.values ?? [];
      final uuidToRowIndex = <String, int>{};

      for (var i = 0; i < existingRows.length; i++) {
        if (existingRows[i].isNotEmpty) {
          final uuid = existingRows[i][0]?.toString() ?? '';
          if (uuid.isNotEmpty) {
            uuidToRowIndex[uuid] = i + 2; // +2 because row 1 is header, and index is 0-based
          }
        }
      }

      // Separate into updates and appends
      final toUpdate = <int, Expense>{};
      final toAppend = <Expense>[];

      for (final expense in expenses) {
        if (expense.uuid != null && uuidToRowIndex.containsKey(expense.uuid)) {
          toUpdate[uuidToRowIndex[expense.uuid]!] = expense;
        } else {
          toAppend.add(expense);
        }
      }

      // Update existing rows using values.update (simpler and more reliable)
      for (final entry in toUpdate.entries) {
        final rowIndex = entry.key;
        final expense = entry.value;
        final range = '$_sheetName!A$rowIndex:I$rowIndex';

        await sheetsApi.spreadsheets.values.update(
          sheets.ValueRange(values: [expense.toSheetRow()]),
          spreadsheetId,
          range,
          valueInputOption: 'RAW',
        );
      }

      // Append new rows
      if (toAppend.isNotEmpty) {
        final appendValues = toAppend.map((e) => e.toSheetRow()).toList();
        await sheetsApi.spreadsheets.values.append(
          sheets.ValueRange(values: appendValues),
          spreadsheetId,
          '$_sheetName!A:I',
          valueInputOption: 'RAW',
          insertDataOption: 'INSERT_ROWS',
        );
      }

      return true;
    } catch (e, stackTrace) {
      debugPrint('Error writing expenses to sheet: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  }

  /// Get spreadsheet name
  Future<String?> getSpreadsheetName(http.Client client, String spreadsheetId) async {
    try {
      final sheetsApi = sheets.SheetsApi(client);
      final spreadsheet = await sheetsApi.spreadsheets.get(spreadsheetId);
      return spreadsheet.properties?.title;
    } catch (e) {
      debugPrint('Error getting spreadsheet name: $e');
      return null;
    }
  }

  /// Check if spreadsheet exists and is accessible
  Future<bool> checkSpreadsheetAccess(http.Client client, String spreadsheetId) async {
    try {
      final sheetsApi = sheets.SheetsApi(client);
      await sheetsApi.spreadsheets.get(spreadsheetId);
      return true;
    } catch (e) {
      debugPrint('Error checking spreadsheet access: $e');
      return false;
    }
  }

  // ==================== SUBSCRIPTIONS ====================

  /// Ensure the Subscriptions sheet exists with headers
  Future<bool> _ensureSubscriptionsSheetExists(
      sheets.SheetsApi sheetsApi, String spreadsheetId) async {
    try {
      final spreadsheet = await sheetsApi.spreadsheets.get(spreadsheetId);
      final sheetExists = spreadsheet.sheets?.any(
            (s) => s.properties?.title == _subscriptionsSheetName,
          ) ??
          false;

      if (!sheetExists) {
        // Create the Subscriptions sheet
        await sheetsApi.spreadsheets.batchUpdate(
          sheets.BatchUpdateSpreadsheetRequest(
            requests: [
              sheets.Request(
                addSheet: sheets.AddSheetRequest(
                  properties: sheets.SheetProperties(
                    title: _subscriptionsSheetName,
                    gridProperties: sheets.GridProperties(frozenRowCount: 1),
                  ),
                ),
              ),
            ],
          ),
          spreadsheetId,
        );

        // Add header row
        await sheetsApi.spreadsheets.values.update(
          sheets.ValueRange(values: [_subscriptionsHeaderRow]),
          spreadsheetId,
          '$_subscriptionsSheetName!A1:K1',
          valueInputOption: 'RAW',
        );
      }
      return true;
    } catch (e) {
      debugPrint('Error ensuring subscriptions sheet exists: $e');
      return false;
    }
  }

  /// Read all subscriptions from spreadsheet
  Future<List<Subscription>> readAllSubscriptions(
      http.Client client, String spreadsheetId) async {
    try {
      final sheetsApi = sheets.SheetsApi(client);

      // Ensure the sheet exists first
      await _ensureSubscriptionsSheetExists(sheetsApi, spreadsheetId);

      final response = await sheetsApi.spreadsheets.values.get(
        spreadsheetId,
        '$_subscriptionsSheetName!A2:K',
      );

      final values = response.values;
      if (values == null || values.isEmpty) {
        return [];
      }

      return values.map((row) => Subscription.fromSheetRow(row)).toList();
    } catch (e) {
      debugPrint('Error reading subscriptions from sheet: $e');
      return [];
    }
  }

  /// Clear all subscription data from spreadsheet (keeps header row)
  Future<bool> clearAllSubscriptionData(
      http.Client client, String spreadsheetId) async {
    try {
      final sheetsApi = sheets.SheetsApi(client);

      // Ensure the sheet exists first
      await _ensureSubscriptionsSheetExists(sheetsApi, spreadsheetId);

      // Clear all data rows (keep header at row 1)
      await sheetsApi.spreadsheets.values.clear(
        sheets.ClearValuesRequest(),
        spreadsheetId,
        '$_subscriptionsSheetName!A2:K',
      );

      debugPrint('Cleared all subscription data from sheet');
      return true;
    } catch (e) {
      debugPrint('Error clearing subscription data from sheet: $e');
      return false;
    }
  }

  /// Write subscriptions to spreadsheet (append or update)
  Future<bool> writeSubscriptions(
    http.Client client,
    String spreadsheetId,
    List<Subscription> subscriptions,
  ) async {
    if (subscriptions.isEmpty) return true;

    try {
      final sheetsApi = sheets.SheetsApi(client);

      // Ensure the sheet exists
      final sheetReady =
          await _ensureSubscriptionsSheetExists(sheetsApi, spreadsheetId);
      if (!sheetReady) {
        debugPrint('Failed to ensure subscriptions sheet exists');
        return false;
      }

      // First, get all existing rows to find UUIDs
      sheets.ValueRange? existingData;
      try {
        existingData = await sheetsApi.spreadsheets.values.get(
          spreadsheetId,
          '$_subscriptionsSheetName!A2:K',
        );
      } catch (e) {
        debugPrint('No existing subscription data found: $e');
      }

      final existingRows = existingData?.values ?? [];
      final uuidToRowIndex = <String, int>{};

      for (var i = 0; i < existingRows.length; i++) {
        if (existingRows[i].isNotEmpty) {
          final uuid = existingRows[i][0]?.toString() ?? '';
          if (uuid.isNotEmpty) {
            uuidToRowIndex[uuid] = i + 2;
          }
        }
      }

      // Separate into updates and appends
      final toUpdate = <int, Subscription>{};
      final toAppend = <Subscription>[];

      for (final subscription in subscriptions) {
        if (uuidToRowIndex.containsKey(subscription.uuid)) {
          toUpdate[uuidToRowIndex[subscription.uuid]!] = subscription;
        } else {
          toAppend.add(subscription);
        }
      }

      // Update existing rows
      for (final entry in toUpdate.entries) {
        final rowIndex = entry.key;
        final subscription = entry.value;
        final range = '$_subscriptionsSheetName!A$rowIndex:K$rowIndex';

        await sheetsApi.spreadsheets.values.update(
          sheets.ValueRange(values: [subscription.toSheetRow()]),
          spreadsheetId,
          range,
          valueInputOption: 'RAW',
        );
      }

      // Append new rows
      if (toAppend.isNotEmpty) {
        final appendValues = toAppend.map((s) => s.toSheetRow()).toList();
        await sheetsApi.spreadsheets.values.append(
          sheets.ValueRange(values: appendValues),
          spreadsheetId,
          '$_subscriptionsSheetName!A:K',
          valueInputOption: 'RAW',
          insertDataOption: 'INSERT_ROWS',
        );
      }

      return true;
    } catch (e, stackTrace) {
      debugPrint('Error writing subscriptions to sheet: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  }
}
