import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/expense_provider.dart';
import '../providers/settings_provider.dart';

class SummaryCard extends StatelessWidget {
  const SummaryCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<ExpenseProvider, SettingsProvider>(
      builder: (context, expenseProvider, settingsProvider, child) {
        final isToday = expenseProvider.isToday;
        final selectedDate = expenseProvider.selectedDate;

        // Format the date label
        String dateLabel;
        if (isToday) {
          dateLabel = 'Today';
        } else {
          dateLabel = DateFormat('EEE, MMM d').format(selectedDate);
        }

        return Card(
          margin: const EdgeInsets.all(16),
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Top row: Selected date total
                Text(
                  dateLabel,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  settingsProvider.formatAmount(expenseProvider.selectedDateTotal),
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                // Bottom row: Weekly and Monthly with totals and averages stacked
                Row(
                  children: [
                    Expanded(
                      child: _PeriodStats(
                        period: isToday ? 'This Week' : 'That Week',
                        total: settingsProvider.formatAmount(expenseProvider.weeklyTotal),
                        average: settingsProvider.formatAmount(expenseProvider.weeklyAverage),
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                    ),
                    Container(
                      height: 70,
                      width: 1,
                      color: Colors.grey[300],
                    ),
                    Expanded(
                      child: _PeriodStats(
                        period: isToday ? 'This Month' : DateFormat('MMM yyyy').format(selectedDate),
                        total: settingsProvider.formatAmount(expenseProvider.monthlyTotal),
                        average: settingsProvider.formatAmount(expenseProvider.monthlyAverage),
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PeriodStats extends StatelessWidget {
  final String period;
  final String total;
  final String average;
  final Color color;

  const _PeriodStats({
    required this.period,
    required this.total,
    required this.average,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          period,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 6),
        // Total - stacked vertically
        Text(
          total,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          'total',
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[500],
          ),
        ),
        const SizedBox(height: 6),
        // Divider between total and avg
        Container(
          width: 80,
          height: 1,
          color: Colors.grey[300],
        ),
        const SizedBox(height: 6),
        // Average - stacked below total
        Text(
          average,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: color.withOpacity(0.7),
          ),
        ),
        Text(
          'avg/day',
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[500],
          ),
        ),
      ],
    );
  }
}
