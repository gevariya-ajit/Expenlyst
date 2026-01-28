import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/sync_provider.dart';

class SyncStatusIndicator extends StatelessWidget {
  final bool showLabel;
  final double size;

  const SyncStatusIndicator({
    super.key,
    this.showLabel = true,
    this.size = 16,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<SyncProvider>(
      builder: (context, syncProvider, child) {
        if (!syncProvider.isSignedIn) {
          return const SizedBox.shrink();
        }

        IconData icon;
        Color color;
        String label;

        switch (syncProvider.syncState) {
          case SyncState.syncing:
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: size,
                  height: size,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                if (showLabel) ...[
                  const SizedBox(width: 8),
                  Text(
                    'Syncing...',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ],
            );
          case SyncState.success:
            icon = Icons.cloud_done;
            color = Colors.green;
            label = 'Synced';
            break;
          case SyncState.error:
            icon = Icons.cloud_off;
            color = Colors.red;
            label = 'Sync failed';
            break;
          case SyncState.idle:
          default:
            if (syncProvider.hasSelectedSheet) {
              icon = Icons.cloud_done_outlined;
              color = Colors.grey;
              label = syncProvider.getLastSyncTimeFormatted();
            } else {
              icon = Icons.cloud_off_outlined;
              color = Colors.grey;
              label = 'Not synced';
            }
            break;
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: size, color: color),
            if (showLabel) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class SyncStatusCard extends StatelessWidget {
  final VoidCallback? onSyncPressed;
  final VoidCallback? onChangeSheetPressed;

  const SyncStatusCard({
    super.key,
    this.onSyncPressed,
    this.onChangeSheetPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<SyncProvider>(
      builder: (context, syncProvider, child) {
        if (!syncProvider.isSignedIn) {
          return const SizedBox.shrink();
        }

        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Sync Status',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    const SyncStatusIndicator(),
                  ],
                ),
                const SizedBox(height: 16),
                if (syncProvider.hasSelectedSheet) ...[
                  Row(
                    children: [
                      Icon(
                        Icons.table_chart,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          syncProvider.selectedSheetName ?? 'Unknown sheet',
                          style: const TextStyle(fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (onChangeSheetPressed != null)
                        TextButton(
                          onPressed: onChangeSheetPressed,
                          child: const Text('Change'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 20,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Last synced: ${syncProvider.getLastSyncTimeFormatted()}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: syncProvider.syncState == SyncState.syncing
                          ? null
                          : onSyncPressed,
                      icon: syncProvider.syncState == SyncState.syncing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync),
                      label: Text(
                        syncProvider.syncState == SyncState.syncing
                            ? 'Syncing...'
                            : 'Sync Now',
                      ),
                    ),
                  ),
                  if (syncProvider.syncError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      syncProvider.syncError!,
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ] else ...[
                  Text(
                    'No spreadsheet selected',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: onChangeSheetPressed,
                      icon: const Icon(Icons.add),
                      label: const Text('Select Spreadsheet'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
