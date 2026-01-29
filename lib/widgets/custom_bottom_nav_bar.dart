import 'package:flutter/material.dart';

class CustomBottomNavBar extends StatelessWidget {
  final VoidCallback onExpensesTap;
  final VoidCallback onSubscriptionsTap;
  final Widget centerButton;

  const CustomBottomNavBar({
    super.key,
    required this.onExpensesTap,
    required this.onSubscriptionsTap,
    required this.centerButton,
  });

  @override
  Widget build(BuildContext context) {
    const double barHeight = 64;
    const double fabSize = 72;
    // 70% inside means 30% sticks out: fabSize * 0.3 = 21.6
    const double fabBottomOffset = barHeight - (fabSize * 0.7);

    return SizedBox(
      height: barHeight + (fabSize * 0.3), // Bar height + protruding part
      child: Stack(
        clipBehavior: Clip.none, // Allow listening indicator to overflow
        alignment: Alignment.bottomCenter,
        children: [
          // Bottom bar container
          Container(
            height: barHeight,
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // Left: All Expenses
                Expanded(
                  child: _NavItem(
                    icon: Icons.list_alt,
                    label: 'Expenses',
                    onTap: onExpensesTap,
                  ),
                ),
                // Center spacer for FAB
                const SizedBox(width: 80),
                // Right: Subscriptions
                Expanded(
                  child: _NavItem(
                    icon: Icons.autorenew,
                    label: 'Subscriptions',
                    onTap: onSubscriptionsTap,
                  ),
                ),
              ],
            ),
          ),
          // Center button positioned with 70% inside the bar
          Positioned(
            bottom: fabBottomOffset,
            child: centerButton,
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 24,
              color: Colors.grey[600],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
