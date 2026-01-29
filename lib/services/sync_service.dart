import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/expense.dart';
import '../models/subscription.dart';
import 'database_service.dart';
import 'sheets_service.dart';

enum SyncResult {
  success,
  noChanges,
  networkError,
  authError,
  sheetError,
  unknownError,
}

class SyncStatus {
  final SyncResult result;
  final int uploaded;
  final int downloaded;
  final String? errorMessage;

  SyncStatus({
    required this.result,
    this.uploaded = 0,
    this.downloaded = 0,
    this.errorMessage,
  });

  bool get isSuccess => result == SyncResult.success || result == SyncResult.noChanges;
}

class SyncService {
  final DatabaseService _databaseService;
  final SheetsService _sheetsService;
  static const _uuid = Uuid();

  SyncService({
    DatabaseService? databaseService,
    SheetsService? sheetsService,
  })  : _databaseService = databaseService ?? DatabaseService(),
        _sheetsService = sheetsService ?? SheetsService();

  /// Full sync: upload local changes, then download remote changes
  Future<SyncStatus> syncAll(
    http.Client client,
    String spreadsheetId,
    DateTime? lastSyncTime,
    String deviceId,
  ) async {
    try {
      // Step 1: Upload local changes to cloud
      final uploadResult = await uploadSync(client, spreadsheetId, lastSyncTime, deviceId);
      if (!uploadResult.isSuccess && uploadResult.result != SyncResult.noChanges) {
        return uploadResult;
      }

      // Step 2: Download remote changes
      final downloadResult = await downloadSync(client, spreadsheetId, lastSyncTime, deviceId);
      if (!downloadResult.isSuccess && downloadResult.result != SyncResult.noChanges) {
        return downloadResult;
      }

      return SyncStatus(
        result: SyncResult.success,
        uploaded: uploadResult.uploaded,
        downloaded: downloadResult.downloaded,
      );
    } catch (e) {
      debugPrint('Error during full sync: $e');
      return SyncStatus(
        result: SyncResult.unknownError,
        errorMessage: e.toString(),
      );
    }
  }

  /// Upload local changes to cloud
  Future<SyncStatus> uploadSync(
    http.Client client,
    String spreadsheetId,
    DateTime? lastSyncTime,
    String deviceId,
  ) async {
    try {
      // Get local expenses modified since last sync
      List<Expense> localChanges;
      if (lastSyncTime != null) {
        localChanges = await _databaseService.getExpensesSince(lastSyncTime);
        debugPrint('Sync: Found ${localChanges.length} changes since $lastSyncTime');
      } else {
        localChanges = await _databaseService.getAllExpensesForSync();
        debugPrint('Sync: Initial sync with ${localChanges.length} expenses');
      }

      // Log deleted expenses
      final deletedCount = localChanges.where((e) => e.isDeleted).length;
      debugPrint('Sync: $deletedCount deleted expenses in changes');

      if (localChanges.isEmpty) {
        debugPrint('Sync: No changes to upload');
        return SyncStatus(result: SyncResult.noChanges);
      }

      // Ensure all expenses have UUID and deviceId
      final expensesToUpload = localChanges.map((e) {
        return e.copyWith(
          uuid: e.uuid ?? _uuid.v4(),
          deviceId: e.deviceId ?? deviceId,
        );
      }).toList();

      // Read existing cloud data for conflict resolution
      final cloudExpenses = await _sheetsService.readAllExpenses(client, spreadsheetId);
      final cloudByUuid = <String, Expense>{};
      for (final expense in cloudExpenses) {
        if (expense.uuid != null) {
          cloudByUuid[expense.uuid!] = expense;
        }
      }

      // Filter: only upload if local is newer (last-write-wins)
      final toUpload = <Expense>[];
      for (final local in expensesToUpload) {
        if (local.uuid == null) continue;

        final cloud = cloudByUuid[local.uuid!];
        if (cloud == null) {
          // New expense, upload it
          toUpload.add(local);
        } else {
          // Compare timestamps for conflict resolution
          final localTime = local.tickerSinceAddUpdate;
          final cloudTime = cloud.tickerSinceAddUpdate;

          if (localTime != null && (cloudTime == null || localTime.isAfter(cloudTime))) {
            toUpload.add(local);
          }
        }
      }

      if (toUpload.isEmpty) {
        return SyncStatus(result: SyncResult.noChanges);
      }

      // Write to cloud
      final success = await _sheetsService.writeExpenses(client, spreadsheetId, toUpload);
      if (!success) {
        return SyncStatus(
          result: SyncResult.sheetError,
          errorMessage: 'Failed to write expenses to sheet',
        );
      }

      return SyncStatus(
        result: SyncResult.success,
        uploaded: toUpload.length,
      );
    } catch (e) {
      debugPrint('Error during upload sync: $e');
      return SyncStatus(
        result: SyncResult.unknownError,
        errorMessage: e.toString(),
      );
    }
  }

  /// Download remote changes to local
  Future<SyncStatus> downloadSync(
    http.Client client,
    String spreadsheetId,
    DateTime? lastSyncTime,
    String deviceId,
  ) async {
    try {
      // Read all cloud expenses
      final cloudExpenses = await _sheetsService.readAllExpenses(client, spreadsheetId);

      if (cloudExpenses.isEmpty) {
        return SyncStatus(result: SyncResult.noChanges);
      }

      int downloadCount = 0;

      for (final cloud in cloudExpenses) {
        if (cloud.uuid == null) continue;

        final local = await _databaseService.getExpenseByUuid(cloud.uuid!);

        if (local == null) {
          // New from cloud, insert locally (unless deleted)
          if (!cloud.isDeleted) {
            await _databaseService.upsertFromSync(cloud);
            downloadCount++;
          }
        } else {
          // Compare timestamps for conflict resolution
          final localTime = local.tickerSinceAddUpdate;
          final cloudTime = cloud.tickerSinceAddUpdate;

          if (cloudTime != null && (localTime == null || cloudTime.isAfter(localTime))) {
            // Cloud is newer, update local
            await _databaseService.upsertFromSync(cloud);
            downloadCount++;
          }
        }
      }

      if (downloadCount == 0) {
        return SyncStatus(result: SyncResult.noChanges);
      }

      return SyncStatus(
        result: SyncResult.success,
        downloaded: downloadCount,
      );
    } catch (e) {
      debugPrint('Error during download sync: $e');
      return SyncStatus(
        result: SyncResult.unknownError,
        errorMessage: e.toString(),
      );
    }
  }

  /// Full restore from cloud (replaces all local data)
  Future<SyncStatus> restoreFromCloud(
    http.Client client,
    String spreadsheetId,
  ) async {
    try {
      // Read all cloud expenses
      final cloudExpenses = await _sheetsService.readAllExpenses(client, spreadsheetId);

      // Clear local database
      await _databaseService.clearAllExpenses();

      int downloadCount = 0;

      // Insert all non-deleted cloud expenses
      for (final expense in cloudExpenses) {
        if (!expense.isDeleted && expense.uuid != null) {
          await _databaseService.upsertFromSync(expense);
          downloadCount++;
        }
      }

      return SyncStatus(
        result: SyncResult.success,
        downloaded: downloadCount,
      );
    } catch (e) {
      debugPrint('Error during restore from cloud: $e');
      return SyncStatus(
        result: SyncResult.unknownError,
        errorMessage: e.toString(),
      );
    }
  }

  /// Initial upload: upload all local expenses to a new sheet
  Future<SyncStatus> initialUpload(
    http.Client client,
    String spreadsheetId,
    String deviceId,
  ) async {
    try {
      final allExpenses = await _databaseService.getAllExpensesForSync();

      if (allExpenses.isEmpty) {
        return SyncStatus(result: SyncResult.noChanges);
      }

      // Ensure all expenses have UUID and deviceId
      final expensesToUpload = allExpenses.map((e) {
        return e.copyWith(
          uuid: e.uuid ?? _uuid.v4(),
          deviceId: e.deviceId ?? deviceId,
        );
      }).toList();

      final success = await _sheetsService.writeExpenses(client, spreadsheetId, expensesToUpload);
      if (!success) {
        return SyncStatus(
          result: SyncResult.sheetError,
          errorMessage: 'Failed to write expenses to sheet',
        );
      }

      return SyncStatus(
        result: SyncResult.success,
        uploaded: expensesToUpload.length,
      );
    } catch (e) {
      debugPrint('Error during initial upload: $e');
      return SyncStatus(
        result: SyncResult.unknownError,
        errorMessage: e.toString(),
      );
    }
  }

  // ==================== SUBSCRIPTIONS SYNC ====================

  /// Sync all subscriptions: upload local, then download remote
  Future<SyncStatus> syncAllSubscriptions(
    http.Client client,
    String spreadsheetId,
  ) async {
    try {
      // Step 1: Upload local subscriptions to cloud
      final uploadResult = await uploadSubscriptions(client, spreadsheetId);
      if (!uploadResult.isSuccess && uploadResult.result != SyncResult.noChanges) {
        return uploadResult;
      }

      // Step 2: Download remote subscriptions
      final downloadResult = await downloadSubscriptions(client, spreadsheetId);
      if (!downloadResult.isSuccess && downloadResult.result != SyncResult.noChanges) {
        return downloadResult;
      }

      return SyncStatus(
        result: SyncResult.success,
        uploaded: uploadResult.uploaded,
        downloaded: downloadResult.downloaded,
      );
    } catch (e) {
      debugPrint('Error during subscriptions sync: $e');
      return SyncStatus(
        result: SyncResult.unknownError,
        errorMessage: e.toString(),
      );
    }
  }

  /// Upload local subscriptions to cloud
  Future<SyncStatus> uploadSubscriptions(
    http.Client client,
    String spreadsheetId,
  ) async {
    try {
      final localSubscriptions = await _databaseService.getAllSubscriptionsForSync();

      if (localSubscriptions.isEmpty) {
        debugPrint('Subscriptions Sync: No subscriptions to upload');
        return SyncStatus(result: SyncResult.noChanges);
      }

      debugPrint('Subscriptions Sync: Uploading ${localSubscriptions.length} subscriptions');

      // Read existing cloud data
      final cloudSubscriptions = await _sheetsService.readAllSubscriptions(client, spreadsheetId);
      final cloudByUuid = <String, Subscription>{};
      for (final sub in cloudSubscriptions) {
        cloudByUuid[sub.uuid] = sub;
      }

      // Filter: only upload if local is newer or new
      final toUpload = <Subscription>[];
      for (final local in localSubscriptions) {
        final cloud = cloudByUuid[local.uuid];
        if (cloud == null) {
          // New subscription, upload it
          toUpload.add(local);
        } else {
          // Compare createdAt for conflict resolution (simpler than expenses)
          if (local.createdAt.isAfter(cloud.createdAt)) {
            toUpload.add(local);
          }
        }
      }

      if (toUpload.isEmpty) {
        return SyncStatus(result: SyncResult.noChanges);
      }

      // Write to cloud
      final success = await _sheetsService.writeSubscriptions(client, spreadsheetId, toUpload);
      if (!success) {
        return SyncStatus(
          result: SyncResult.sheetError,
          errorMessage: 'Failed to write subscriptions to sheet',
        );
      }

      return SyncStatus(
        result: SyncResult.success,
        uploaded: toUpload.length,
      );
    } catch (e) {
      debugPrint('Error during subscriptions upload: $e');
      return SyncStatus(
        result: SyncResult.unknownError,
        errorMessage: e.toString(),
      );
    }
  }

  /// Download remote subscriptions to local
  Future<SyncStatus> downloadSubscriptions(
    http.Client client,
    String spreadsheetId,
  ) async {
    try {
      final cloudSubscriptions = await _sheetsService.readAllSubscriptions(client, spreadsheetId);

      if (cloudSubscriptions.isEmpty) {
        return SyncStatus(result: SyncResult.noChanges);
      }

      int downloadCount = 0;

      for (final cloud in cloudSubscriptions) {
        final local = await _databaseService.getSubscriptionByUuid(cloud.uuid);

        if (local == null) {
          // New from cloud, insert locally (unless deleted)
          if (!cloud.isDeleted) {
            await _databaseService.upsertSubscriptionFromSync(cloud);
            downloadCount++;
          }
        } else {
          // Compare timestamps for conflict resolution
          if (cloud.createdAt.isAfter(local.createdAt)) {
            await _databaseService.upsertSubscriptionFromSync(cloud);
            downloadCount++;
          }
        }
      }

      if (downloadCount == 0) {
        return SyncStatus(result: SyncResult.noChanges);
      }

      return SyncStatus(
        result: SyncResult.success,
        downloaded: downloadCount,
      );
    } catch (e) {
      debugPrint('Error during subscriptions download: $e');
      return SyncStatus(
        result: SyncResult.unknownError,
        errorMessage: e.toString(),
      );
    }
  }
}
