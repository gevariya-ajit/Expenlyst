import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/subscription.dart';

class SubscriptionCard extends StatelessWidget {
  final Subscription subscription;
  final String currencySymbol;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final ValueChanged<bool>? onToggleActive;

  const SubscriptionCard({
    super.key,
    required this.subscription,
    required this.currencySymbol,
    this.onEdit,
    this.onDelete,
    this.onToggleActive,
  });

  /// Platform icons
  static const Map<String, IconData> platformIcons = {
    'Netflix': Icons.movie,
    'Amazon Prime': Icons.shopping_bag,
    'Disney+ Hotstar': Icons.stars,
    'Zee5': Icons.tv,
    'SonyLIV': Icons.live_tv,
    'YouTube Premium': Icons.play_circle,
    'KuKu FM': Icons.podcasts,
    'Tangy TV': Icons.smart_display,
    'Spotify': Icons.music_note,
    'Apple Music': Icons.library_music,
    'JioCinema': Icons.videocam,
    'MX Player': Icons.ondemand_video,
    'Voot': Icons.video_library,
    'ALTBalaji': Icons.play_arrow,
    'Eros Now': Icons.movie_filter,
    'Lionsgate Play': Icons.theaters,
    'Discovery+': Icons.explore,
    'Audible': Icons.headphones,
  };

  /// Platform colors
  static const Map<String, Color> platformColors = {
    'Netflix': Color(0xFFE50914),
    'Amazon Prime': Color(0xFF00A8E1),
    'Disney+ Hotstar': Color(0xFF1A2A4E),
    'Zee5': Color(0xFF8230C6),
    'SonyLIV': Color(0xFF000000),
    'YouTube Premium': Color(0xFFFF0000),
    'KuKu FM': Color(0xFF6B4EE6),
    'Tangy TV': Color(0xFFFF6B35),
    'Spotify': Color(0xFF1DB954),
    'Apple Music': Color(0xFFFC3C44),
    'JioCinema': Color(0xFF0A2885),
    'MX Player': Color(0xFF0087D1),
    'Voot': Color(0xFFF36E25),
    'ALTBalaji': Color(0xFFFF0000),
    'Eros Now': Color(0xFFE31937),
    'Lionsgate Play': Color(0xFFFBB03B),
    'Discovery+': Color(0xFF003366),
    'Audible': Color(0xFFFF9900),
  };

  static IconData getPlatformIcon(String platform) {
    return platformIcons[platform] ?? Icons.subscriptions;
  }

  static Color getPlatformColor(String platform) {
    return platformColors[platform] ?? const Color(0xFF9E9E9E);
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d, yyyy');
    final platformIcon = getPlatformIcon(subscription.platform);
    final platformColor = getPlatformColor(subscription.platform);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Platform icon
              CircleAvatar(
                radius: 24,
                backgroundColor: platformColor.withOpacity(0.15),
                child: Icon(
                  platformIcon,
                  color: platformColor,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              // Platform name and dates
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subscription.platform,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: subscription.isActive
                            ? null
                            : (isDark ? Colors.grey[500] : Colors.grey[600]),
                        decoration: subscription.isActive
                            ? null
                            : TextDecoration.lineThrough,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (subscription.nextPaymentDate != null)
                      Text(
                        'Next: ${dateFormat.format(subscription.nextPaymentDate!)}',
                        style: TextStyle(
                          color: _getNextPaymentColor(context),
                          fontSize: 13,
                        ),
                      )
                    else
                      Text(
                        'Last: ${dateFormat.format(subscription.lastPaymentDate)}',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 13,
                        ),
                      ),
                    if (subscription.bankName != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subscription.bankName!,
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Amount and frequency
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$currencySymbol${_formatAmount(subscription.amount)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: subscription.isActive
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: platformColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      subscription.frequency.shortName,
                      style: TextStyle(
                        fontSize: 12,
                        color: platformColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              // Menu button
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert,
                  color: Colors.grey[600],
                ),
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      onEdit?.call();
                      break;
                    case 'toggle':
                      onToggleActive?.call(!subscription.isActive);
                      break;
                    case 'delete':
                      onDelete?.call();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 20),
                        SizedBox(width: 12),
                        Text('Edit'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Row(
                      children: [
                        Icon(
                          subscription.isActive
                              ? Icons.pause_circle
                              : Icons.play_circle,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(subscription.isActive ? 'Pause' : 'Resume'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 20, color: Colors.red),
                        SizedBox(width: 12),
                        Text('Delete', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getNextPaymentColor(BuildContext context) {
    if (subscription.nextPaymentDate == null) {
      return Colors.grey[600]!;
    }

    final daysUntilPayment =
        subscription.nextPaymentDate!.difference(DateTime.now()).inDays;

    if (daysUntilPayment < 0) {
      return Colors.red;
    } else if (daysUntilPayment <= 3) {
      return Colors.orange;
    } else if (daysUntilPayment <= 7) {
      return Colors.amber[700]!;
    } else {
      return Colors.grey[600]!;
    }
  }

  String _formatAmount(double amount) {
    if (amount == amount.roundToDouble()) {
      return amount.toInt().toString();
    }
    return amount.toStringAsFixed(2);
  }
}

/// Summary card showing total monthly cost
class SubscriptionSummaryCard extends StatelessWidget {
  final double totalMonthlyCost;
  final int subscriptionCount;
  final String currencySymbol;

  const SubscriptionSummaryCard({
    super.key,
    required this.totalMonthlyCost,
    required this.subscriptionCount,
    required this.currencySymbol,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor:
                  Theme.of(context).colorScheme.primary.withOpacity(0.2),
              child: Icon(
                Icons.subscriptions,
                color: Theme.of(context).colorScheme.primary,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Monthly Total',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context)
                          .colorScheme
                          .onPrimaryContainer
                          .withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$currencySymbol${_formatAmount(totalMonthlyCost)}',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  subscriptionCount.toString(),
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                Text(
                  subscriptionCount == 1 ? 'subscription' : 'subscriptions',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context)
                        .colorScheme
                        .onPrimaryContainer
                        .withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatAmount(double amount) {
    if (amount == amount.roundToDouble()) {
      return amount.toInt().toString();
    }
    return amount.toStringAsFixed(2);
  }
}
