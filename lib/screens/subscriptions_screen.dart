import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/subscription.dart';
import '../providers/subscription_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/subscription_card.dart';

class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  @override
  void initState() {
    super.initState();
    debugPrint('[UI] initState called');
    // Load subscriptions when screen opens (only if not already scanning)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<SubscriptionProvider>();
      debugPrint('[UI] postFrameCallback - scanStatus=${provider.scanStatus}');
      if (provider.scanStatus != ScanStatus.scanning) {
        debugPrint('[UI] Calling loadSubscriptions from initState');
        provider.loadSubscriptions();
      } else {
        debugPrint('[UI] Skipping loadSubscriptions - already scanning');
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
            GestureDetector(
              onLongPress: () => _scanSms(context, clearExisting: true),
              child: IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Scan SMS (long press to clear all)',
                onPressed: () => _scanSms(context, clearExisting: false),
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
    debugPrint('[UI] _buildContent called - scanStatus=${provider.scanStatus}, subscriptions=${provider.activeSubscriptions.length}');

    // Show scanning state as a full-screen indicator
    if (provider.scanStatus == ScanStatus.scanning) {
      debugPrint('[UI] Showing SCANNING indicator');
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
                'Looking for OTT subscriptions...',
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
      debugPrint('[UI] Showing EMPTY state');
      return _buildEmptyState(context);
    }

    debugPrint('[UI] Showing SUBSCRIPTIONS list with ${subscriptions.length} items');
    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        // Merge suggestion cards
        if (provider.potentialDuplicates.isNotEmpty)
          ...provider.potentialDuplicates.map((group) => _buildMergeSuggestionCard(
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

        // Subscription list
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Active Subscriptions',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ...subscriptions.map((subscription) => SubscriptionCard(
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
                  )),
            ],
          ),
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
                  ? 'Scan your bank SMS to automatically detect OTT subscriptions like Netflix, Amazon Prime, and more.'
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
    // Build description showing each subscription's amount and day
    final details = group
        .map((s) => '$currencySymbol${s.amount.toStringAsFixed(0)} (day ${s.lastPaymentDate.day})')
        .join(', ');

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
            const SizedBox(height: 12),
            Text(
              details,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              'Merge to keep only the most recent one.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => provider.dismissDuplicateSuggestion(group),
                  child: const Text('Keep All'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _confirmMerge(context, group, provider),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber.shade700,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Merge'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmMerge(
    BuildContext context,
    List<Subscription> group,
    SubscriptionProvider provider,
  ) {
    // Sort to find which one will be kept (most recent)
    final sorted = List<Subscription>.from(group)
      ..sort((a, b) => b.lastPaymentDate.compareTo(a.lastPaymentDate));
    final toKeep = sorted.first;
    final currencySymbol = context.read<SettingsProvider>().currencySymbol;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Merge Subscriptions'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Will keep: ${toKeep.platform} ($currencySymbol${toKeep.amount.toStringAsFixed(0)})',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              'Will remove ${group.length - 1} other subscription(s).',
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
              provider.mergeSubscriptions(group);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Subscriptions merged')),
              );
            },
            child: const Text('Merge'),
          ),
        ],
      ),
    );
  }

  Future<void> _scanSms(BuildContext context, {bool clearExisting = false}) async {
    final provider = context.read<SubscriptionProvider>();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(clearExisting
            ? 'Full refresh - clearing existing subscriptions...'
            : 'Scanning for new subscriptions...'),
        duration: const Duration(seconds: 1),
      ),
    );

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
