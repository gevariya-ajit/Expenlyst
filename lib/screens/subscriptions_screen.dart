import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/subscription.dart';
import '../providers/subscription_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/sync_provider.dart';
import '../widgets/subscription_card.dart';

class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  bool _showAllSubscriptions = false;
  bool _showAllMatrimony = false;
  // Track selected subscription UUIDs per platform for selective merge
  final Map<String, Set<String>> _selectedForMerge = {};

  @override
  void initState() {
    super.initState();
    // Load subscriptions when screen opens (only if not already scanning)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<SubscriptionProvider>();
      if (provider.scanStatus != ScanStatus.scanning) {
        provider.loadSubscriptions();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscriptions'),
        actions: [
          if (Platform.isAndroid)
            InkWell(
              onTap: () => _scanSms(context, clearExisting: false),
              onLongPress: () => _scanSms(context, clearExisting: true),
              customBorder: const CircleBorder(),
              child: const Padding(
                padding: EdgeInsets.all(8.0),
                child: Icon(Icons.refresh),
              ),
            ),
        ],
      ),
      body: Consumer2<SubscriptionProvider, SettingsProvider>(
        builder: (context, subscriptionProvider, settingsProvider, child) {
          return Column(
            children: [
              // Scan status banner
              _buildScanStatusBanner(context, subscriptionProvider),

              // Content
              Expanded(
                child: _buildContent(
                    context, subscriptionProvider, settingsProvider),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context),
        tooltip: 'Add Subscription',
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildScanStatusBanner(
      BuildContext context, SubscriptionProvider provider) {
    switch (provider.scanStatus) {
      case ScanStatus.scanning:
        // Full-screen scanning indicator is shown in _buildContent
        return const SizedBox.shrink();

      case ScanStatus.completed:
        return Container(
          color: Colors.green.withOpacity(0.1),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  provider.newSubscriptionsFound > 0
                      ? 'Found ${provider.newSubscriptionsFound} new subscription(s)'
                      : 'No new subscriptions found',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              TextButton(
                onPressed: () => provider.resetScanStatus(),
                child: const Text('Dismiss'),
              ),
            ],
          ),
        );

      case ScanStatus.error:
        return Container(
          color: Colors.red.withOpacity(0.1),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.error, color: Colors.red),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  provider.errorMessage ?? 'An error occurred',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              TextButton(
                onPressed: () => provider.resetScanStatus(),
                child: const Text('Dismiss'),
              ),
            ],
          ),
        );

      case ScanStatus.permissionDenied:
        return Container(
          color: Colors.orange.withOpacity(0.1),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.warning, color: Colors.orange),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'SMS permission denied. Enable in settings.',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              TextButton(
                onPressed: () => provider.openSettings(),
                child: const Text('Settings'),
              ),
            ],
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildContent(BuildContext context, SubscriptionProvider provider,
      SettingsProvider settingsProvider) {
    // Show scanning state as a full-screen indicator
    if (provider.scanStatus == ScanStatus.scanning) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 60,
                height: 60,
                child: CircularProgressIndicator(strokeWidth: 4),
              ),
              const SizedBox(height: 24),
              const Text(
                'Scanning SMS messages...',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (provider.scanTotal > 0) ...[
                const SizedBox(height: 12),
                Text(
                  '${provider.scanProgress} of ${provider.scanTotal}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: 200,
                  child: LinearProgressIndicator(
                    value: provider.scanTotal > 0
                        ? provider.scanProgress / provider.scanTotal
                        : null,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'Looking for subscriptions...',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final subscriptions = provider.activeSubscriptions;

    if (subscriptions.isEmpty) {
      return _buildEmptyState(context);
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        // Merge suggestion cards
        if (provider.potentialDuplicates.isNotEmpty)
          ...provider.potentialDuplicates.map((group) =>
              _buildMergeSuggestionCard(
                context,
                group,
                settingsProvider.currencySymbol,
                provider,
              )),

        // Summary card
        SubscriptionSummaryCard(
          totalMonthlyCost: provider.totalMonthlyCost,
          subscriptionCount: subscriptions.length,
          currencySymbol: settingsProvider.currencySymbol,
          remainingThisMonth: provider.remainingThisMonth,
          nextMonthTotal: provider.nextMonthTotal,
        ),

        const SizedBox(height: 8),

        // OTT subscriptions card
        _buildCategoryCard(
          context: context,
          subscriptions: subscriptions,
          currencySymbol: settingsProvider.currencySymbol,
          provider: provider,
          category: SubscriptionCategory.ott,
          title: 'OTT',
          icon: Icons.live_tv,
          color: Theme.of(context).colorScheme.primary,
          backgroundColor: const Color(0xFFE8F5F3),
          showAll: _showAllSubscriptions,
          onToggleShowAll: () {
            setState(() {
              _showAllSubscriptions = !_showAllSubscriptions;
            });
          },
        ),

        // Matrimony subscriptions card
        _buildCategoryCard(
          context: context,
          subscriptions: subscriptions,
          currencySymbol: settingsProvider.currencySymbol,
          provider: provider,
          category: SubscriptionCategory.matrimony,
          title: 'Matrimony',
          icon: Icons.favorite,
          color: const Color(0xFFE91E63),
          backgroundColor: const Color(0xFFFCE4EC),
          showAll: _showAllMatrimony,
          onToggleShowAll: () {
            setState(() {
              _showAllMatrimony = !_showAllMatrimony;
            });
          },
        ),

        // Inactive subscriptions
        if (provider.subscriptions
            .where((s) => !s.isActive && !s.isDeleted)
            .isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Paused Subscriptions',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: provider.subscriptions
                  .where((s) => !s.isActive && !s.isDeleted)
                  .map((subscription) => SubscriptionCard(
                        subscription: subscription,
                        currencySymbol: settingsProvider.currencySymbol,
                        onEdit: () => _showEditDialog(context, subscription),
                        onDelete: () =>
                            _confirmDelete(context, subscription),
                        onToggleActive: (isActive) {
                          if (subscription.id != null) {
                            provider.toggleSubscriptionActive(
                                subscription.id!, isActive);
                          }
                        },
                      ))
                  .toList(),
            ),
          ),
        ],
      ],
    );
  }

  /// Build a category-specific subscriptions card
  Widget _buildCategoryCard({
    required BuildContext context,
    required List<Subscription> subscriptions,
    required String currencySymbol,
    required SubscriptionProvider provider,
    required SubscriptionCategory category,
    required String title,
    required IconData icon,
    required Color color,
    required Color backgroundColor,
    required bool showAll,
    required VoidCallback onToggleShowAll,
  }) {
    final filtered = subscriptions
        .where((s) => s.category == category)
        .toList()
      ..sort((a, b) {
        final aDate = a.nextPaymentDate ?? DateTime(2100);
        final bDate = b.nextPaymentDate ?? DateTime(2100);
        return aDate.compareTo(bDate);
      });

    if (filtered.isEmpty) {
      return const SizedBox.shrink();
    }

    const initialCount = 4;
    final hasMore = filtered.length > initialCount;
    final displayList =
        showAll ? filtered : filtered.take(initialCount).toList();

    final monthlyCost = provider.monthlyCostForCategory(category);
    final remaining = provider.remainingThisMonthForCategory(category);
    final nextMonth = provider.nextMonthTotalForCategory(category);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: backgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  '$title (${filtered.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          // Category cost breakdown
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                _buildCategoryStat(
                    'Monthly', '$currencySymbol${_formatAmount(monthlyCost)}', color),
                const SizedBox(width: 16),
                _buildCategoryStat(
                    'Remaining', '$currencySymbol${_formatAmount(remaining)}', color),
                const SizedBox(width: 16),
                _buildCategoryStat(
                    'Next mo', '$currencySymbol${_formatAmount(nextMonth)}', color),
              ],
            ),
          ),

          // Subscription items
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: displayList
                  .map((subscription) => SubscriptionCard(
                        subscription: subscription,
                        currencySymbol: currencySymbol,
                        onEdit: () => _showEditDialog(context, subscription),
                        onDelete: () => _confirmDelete(context, subscription),
                        onToggleActive: (isActive) {
                          if (subscription.id != null) {
                            provider.toggleSubscriptionActive(
                                subscription.id!, isActive);
                          }
                        },
                      ))
                  .toList(),
            ),
          ),

          // See all / Show less
          if (hasMore)
            InkWell(
              onTap: onToggleShowAll,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: Colors.grey.withOpacity(0.2),
                    ),
                  ),
                ),
                child: Center(
                  child: Text(
                    showAll
                        ? 'Show less'
                        : 'See all (${filtered.length})',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final isAndroid = Platform.isAndroid;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.subscriptions,
              size: 80,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'No Subscriptions Yet',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isAndroid
                  ? 'Scan your bank SMS to automatically detect subscriptions like Netflix, Amazon Prime, Shaadi, and more.'
                  : 'Add your subscriptions manually to track your recurring expenses.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            if (isAndroid)
              ElevatedButton.icon(
                onPressed: () => _scanSms(context),
                icon: const Icon(Icons.sms),
                label: const Text('Scan SMS'),
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
              ),
            if (isAndroid) const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => _showAddDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Add Manually'),
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMergeSuggestionCard(
    BuildContext context,
    List<Subscription> group,
    String currencySymbol,
    SubscriptionProvider provider,
  ) {
    final platform = group.first.platform;
    final platformKey = platform.toLowerCase();

    // Initialize selection set if not present
    _selectedForMerge.putIfAbsent(platformKey, () => {});
    final selected = _selectedForMerge[platformKey]!;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.amber.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.amber.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.help_outline, color: Colors.amber.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Multiple $platform subscriptions',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.amber.shade900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Select duplicates to merge (keeps most recent):',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            // Select All row
            InkWell(
              onTap: () {
                setState(() {
                  if (selected.length == group.length) {
                    selected.clear();
                  } else {
                    selected.addAll(group.map((s) => s.uuid));
                  }
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: selected.length == group.length
                            ? true
                            : selected.isEmpty
                                ? false
                                : null,
                        tristate: true,
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              selected.addAll(group.map((s) => s.uuid));
                            } else {
                              selected.clear();
                            }
                          });
                        },
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Select All',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: Colors.amber.shade200),
            const SizedBox(height: 4),
            // Each subscription as a selectable row
            ...group.map((sub) {
              final isSelected = selected.contains(sub.uuid);
              return InkWell(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      selected.remove(sub.uuid);
                    } else {
                      selected.add(sub.uuid);
                    }
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: isSelected,
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                selected.add(sub.uuid);
                              } else {
                                selected.remove(sub.uuid);
                              }
                            });
                          },
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$currencySymbol${sub.amount.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '(day ${sub.lastPaymentDate.day})',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    _selectedForMerge.remove(platformKey);
                    provider.dismissDuplicateSuggestion(group);
                  },
                  child: const Text('Dismiss'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: selected.length >= 2
                      ? () => _confirmMergeSelected(
                          context, group, selected, provider)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber.shade700,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                  ),
                  child: Text(selected.length >= 2
                      ? 'Merge ${selected.length} Selected'
                      : 'Select 2+ to Merge'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmMergeSelected(
    BuildContext context,
    List<Subscription> group,
    Set<String> selectedUuids,
    SubscriptionProvider provider,
  ) {
    final selectedSubs =
        group.where((s) => selectedUuids.contains(s.uuid)).toList();
    if (selectedSubs.length < 2) return;

    // Sort to find which one will be kept (most recent)
    selectedSubs.sort((a, b) => b.lastPaymentDate.compareTo(a.lastPaymentDate));
    final toKeep = selectedSubs.first;
    final toRemove = selectedSubs.skip(1).toList();
    final currencySymbol = context.read<SettingsProvider>().currencySymbol;

    var selectedFrequency = toKeep.frequency;
    var selectedCategory = toKeep.category;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Merge Subscriptions'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Keep:',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${toKeep.platform} - $currencySymbol${toKeep.amount.toStringAsFixed(0)} (day ${toKeep.lastPaymentDate.day})',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Text(
                'Remove:',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 4),
              ...toRemove.map((s) => Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      '$currencySymbol${s.amount.toStringAsFixed(0)} (day ${s.lastPaymentDate.day})',
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  )),
              const SizedBox(height: 16),
              // Frequency dropdown
              DropdownButtonFormField<SubscriptionFrequency>(
                value: selectedFrequency,
                decoration: const InputDecoration(
                  labelText: 'Frequency',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: SubscriptionFrequency.values.map((freq) {
                  return DropdownMenuItem(
                    value: freq,
                    child: Text(freq.displayName),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() {
                      selectedFrequency = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              // Category dropdown
              DropdownButtonFormField<SubscriptionCategory>(
                value: selectedCategory,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: SubscriptionCategory.values.map((cat) {
                  return DropdownMenuItem(
                    value: cat,
                    child: Text(cat.displayName),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() {
                      selectedCategory = value;
                    });
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                provider.mergeSubscriptions(
                  selectedSubs,
                  frequency: selectedFrequency,
                  category: selectedCategory,
                );
                // Clean up selection state
                final platformKey = group.first.platform.toLowerCase();
                _selectedForMerge.remove(platformKey);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(
                          'Merged ${selectedSubs.length} subscriptions')),
                );
              },
              child: const Text('Merge'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _scanSms(BuildContext context, {bool clearExisting = false}) async {
    final provider = context.read<SubscriptionProvider>();

    // Reset merge selection state on new scan
    _selectedForMerge.clear();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(clearExisting
            ? 'Full refresh - clearing existing subscriptions...'
            : 'Scanning for new subscriptions...'),
        duration: const Duration(seconds: 1),
      ),
    );

    // Clear subscriptions from Google Sheet before full rescan
    if (clearExisting) {
      final syncProvider = context.read<SyncProvider>();
      if (syncProvider.isSignedIn && syncProvider.hasSelectedSheet) {
        await syncProvider.clearSheetSubscriptions();
      }
    }

    await provider.scanSms(clearExisting: clearExisting);

    if (!mounted) return;

    // Show result
    if (provider.scanStatus == ScanStatus.permissionDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SMS permission denied. Please enable in Settings.'),
          duration: Duration(seconds: 3),
        ),
      );
    } else if (provider.scanStatus == ScanStatus.error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${provider.errorMessage}'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showAddDialog(BuildContext context) {
    _showSubscriptionDialog(context, null);
  }

  void _showEditDialog(BuildContext context, Subscription subscription) {
    _showSubscriptionDialog(context, subscription);
  }

  void _showSubscriptionDialog(
      BuildContext context, Subscription? subscription) {
    final isEditing = subscription != null;
    final platformController =
        TextEditingController(text: subscription?.platform ?? '');
    final amountController = TextEditingController(
        text: subscription?.amount.toString() ?? '');
    var selectedFrequency =
        subscription?.frequency ?? SubscriptionFrequency.monthly;
    var selectedCategory =
        subscription?.category ?? SubscriptionCategory.ott;
    var selectedDate = subscription?.lastPaymentDate ?? DateTime.now();

    final settingsProvider = context.read<SettingsProvider>();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: SingleChildScrollView(
            child: Container(
              width: double.maxFinite,
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isEditing ? 'Edit Subscription' : 'Add Subscription',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),

                  // Platform name
                  TextField(
                    controller: platformController,
                    decoration: const InputDecoration(
                      labelText: 'Platform Name',
                      hintText: 'e.g., Netflix, Spotify',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 16),

                  // Amount
                  TextField(
                    controller: amountController,
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      border: const OutlineInputBorder(),
                      prefixText: '${settingsProvider.currencySymbol} ',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 16),

                  // Frequency dropdown
                  DropdownButtonFormField<SubscriptionFrequency>(
                    value: selectedFrequency,
                    decoration: const InputDecoration(
                      labelText: 'Frequency',
                      border: OutlineInputBorder(),
                    ),
                    items: SubscriptionFrequency.values.map((freq) {
                      return DropdownMenuItem(
                        value: freq,
                        child: Text(freq.displayName),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          selectedFrequency = value;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),

                  // Category dropdown
                  DropdownButtonFormField<SubscriptionCategory>(
                    value: selectedCategory,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                    ),
                    items: SubscriptionCategory.values.map((cat) {
                      return DropdownMenuItem(
                        value: cat,
                        child: Text(cat.displayName),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          selectedCategory = value;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),

                  // Last payment date
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate:
                            DateTime.now().subtract(const Duration(days: 365)),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() {
                          selectedDate = picked;
                        });
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Last Payment Date',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today),
                      ),
                      child: Text(
                        '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () {
                          final platform = platformController.text.trim();
                          final amount =
                              double.tryParse(amountController.text) ?? 0;

                          if (platform.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text('Please enter a platform name')),
                            );
                            return;
                          }

                          if (amount <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Please enter a valid amount')),
                            );
                            return;
                          }

                          final provider =
                              this.context.read<SubscriptionProvider>();

                          if (isEditing) {
                            final updated = subscription.copyWith(
                              platform: platform,
                              amount: amount,
                              frequency: selectedFrequency,
                              category: selectedCategory,
                              lastPaymentDate: selectedDate,
                              nextPaymentDate: _calculateNextPaymentDate(
                                  selectedDate, selectedFrequency),
                            );
                            provider.updateSubscription(updated);
                          } else {
                            final newSubscription = Subscription(
                              platform: platform,
                              category: selectedCategory,
                              amount: amount,
                              frequency: selectedFrequency,
                              lastPaymentDate: selectedDate,
                              nextPaymentDate: _calculateNextPaymentDate(
                                  selectedDate, selectedFrequency),
                            );
                            provider.addSubscription(newSubscription);
                          }

                          Navigator.of(ctx).pop();
                        },
                        child: Text(isEditing ? 'Save' : 'Add'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryStat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey[600]),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  String _formatAmount(double amount) {
    if (amount == amount.roundToDouble()) {
      return amount.toInt().toString();
    }
    return amount.toStringAsFixed(2);
  }

  DateTime _calculateNextPaymentDate(
      DateTime lastPayment, SubscriptionFrequency frequency) {
    return DateTime(
      lastPayment.year,
      lastPayment.month + frequency.monthsPerCycle,
      lastPayment.day,
    );
  }

  void _confirmDelete(BuildContext context, Subscription subscription) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Subscription'),
        content: Text(
            'Are you sure you want to delete "${subscription.platform}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              if (subscription.id != null) {
                context
                    .read<SubscriptionProvider>()
                    .deleteSubscription(subscription.id!);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text('${subscription.platform} deleted')),
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
