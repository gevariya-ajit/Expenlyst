import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/all_expenses_screen.dart';

class ExpenseList extends StatefulWidget {
  const ExpenseList({super.key});

  static const Map<String, IconData> categoryIcons = {
    // Household
    'Household': Icons.home,
    'Rent': Icons.apartment,
    'Maintenance': Icons.build,
    'Electricity': Icons.bolt,
    'Water': Icons.water_drop,
    'Gas': Icons.local_fire_department,
    'Internet': Icons.wifi,
    'Mobile Recharge': Icons.phone_android,
    'OTT Subscriptions': Icons.subscriptions,

    // Food & Dining
    'Groceries': Icons.shopping_cart,
    'Vegetables & Fruits': Icons.eco,
    'Milk & Dairy': Icons.breakfast_dining,
    'Snacks': Icons.cookie,
    'Restaurants': Icons.restaurant,
    'Food Orders': Icons.delivery_dining,

    // Transportation
    'Fuel': Icons.local_gas_station,
    'Public Transport': Icons.directions_bus,
    'Cab': Icons.local_taxi,
    'Vehicle Maintenance': Icons.car_repair,
    'Parking': Icons.local_parking,
    'Toll': Icons.toll,
    'Car EMI': Icons.car_rental,

    // Shopping
    'Clothing': Icons.checkroom,
    'Footwear': Icons.ice_skating,
    'Accessories': Icons.watch,
    'Online Shopping': Icons.shopping_bag,
    'Electronics': Icons.devices,
    'Home Essentials': Icons.cleaning_services,

    // Health & Medical
    'Doctor': Icons.local_hospital,
    'Medicines': Icons.medication,
    'Insurance Premium': Icons.security,
    'Gym': Icons.fitness_center,

    // Education
    'School Fees': Icons.school,
    'Coaching': Icons.class_,
    'Online Courses': Icons.ondemand_video,
    'Books & Stationery': Icons.menu_book,

    // Entertainment & Leisure
    'Movies': Icons.movie,
    'Games': Icons.sports_esports,
    'Travel': Icons.flight,
    'Events': Icons.event,
    'Hobbies': Icons.palette,

    // Work & Business
    'Office Supplies': Icons.business_center,
    'Software': Icons.computer,
    'Work Travel': Icons.work,
    'Client Expenses': Icons.handshake,

    // Financial
    'Loan EMI': Icons.account_balance,
    'Credit Card': Icons.credit_card,
    'Investments': Icons.trending_up,
    'Taxes': Icons.receipt_long,
    'Savings': Icons.savings,

    // Personal & Family
    'Personal Care': Icons.face,
    'Salon': Icons.content_cut,
    'Kids': Icons.child_care,
    'Gifts': Icons.card_giftcard,
    'Donations': Icons.volunteer_activism,

    // Others
    'Pet Care': Icons.pets,
    'Repairs': Icons.handyman,
    'Emergency': Icons.emergency,
    'Matrimony': Icons.favorite,
    'Car Maintenance': Icons.car_repair,
    'Miscellaneous': Icons.more_horiz,
  };

  static const Map<String, Color> categoryColors = {
    // Household - Browns/Oranges
    'Household': Color(0xFF8D6E63),
    'Rent': Color(0xFF795548),
    'Maintenance': Color(0xFFA1887F),
    'Electricity': Color(0xFFFFB300),
    'Water': Color(0xFF29B6F6),
    'Gas': Color(0xFFFF7043),
    'Internet': Color(0xFF5C6BC0),
    'Mobile Recharge': Color(0xFF26A69A),
    'OTT Subscriptions': Color(0xFFE91E63),

    // Food & Dining - Oranges/Reds
    'Groceries': Color(0xFF66BB6A),
    'Vegetables & Fruits': Color(0xFF4CAF50),
    'Milk & Dairy': Color(0xFFFFEE58),
    'Snacks': Color(0xFFFFCA28),
    'Restaurants': Color(0xFFFF7043),
    'Food Orders': Color(0xFFFF5722),

    // Transportation - Blues
    'Fuel': Color(0xFF42A5F5),
    'Public Transport': Color(0xFF5C6BC0),
    'Cab': Color(0xFF26C6DA),
    'Vehicle Maintenance': Color(0xFF78909C),
    'Parking': Color(0xFF7E57C2),
    'Toll': Color(0xFF9575CD),
    'Car EMI': Color(0xFF3F51B5),

    // Shopping - Pinks/Purples
    'Clothing': Color(0xFFEC407A),
    'Footwear': Color(0xFFAB47BC),
    'Accessories': Color(0xFFBA68C8),
    'Online Shopping': Color(0xFFFF4081),
    'Electronics': Color(0xFF7C4DFF),
    'Home Essentials': Color(0xFF80CBC4),

    // Health & Medical - Greens/Teals
    'Doctor': Color(0xFF26A69A),
    'Medicines': Color(0xFF66BB6A),
    'Insurance Premium': Color(0xFF009688),
    'Gym': Color(0xFF00BCD4),

    // Education - Indigos
    'School Fees': Color(0xFF3F51B5),
    'Coaching': Color(0xFF5C6BC0),
    'Online Courses': Color(0xFF7986CB),
    'Books & Stationery': Color(0xFF9FA8DA),

    // Entertainment & Leisure - Purples/Pinks
    'Movies': Color(0xFF9C27B0),
    'Games': Color(0xFF7B1FA2),
    'Travel': Color(0xFFE91E63),
    'Events': Color(0xFFF06292),
    'Hobbies': Color(0xFFCE93D8),

    // Work & Business - Grays/Blues
    'Office Supplies': Color(0xFF607D8B),
    'Software': Color(0xFF455A64),
    'Work Travel': Color(0xFF546E7A),
    'Client Expenses': Color(0xFF78909C),

    // Financial - Greens/Golds
    'Loan EMI': Color(0xFF43A047),
    'Credit Card': Color(0xFFE53935),
    'Investments': Color(0xFF00C853),
    'Taxes': Color(0xFFFF6F00),
    'Savings': Color(0xFF2E7D32),

    // Personal & Family - Warm colors
    'Personal Care': Color(0xFFFF8A80),
    'Salon': Color(0xFFFF80AB),
    'Kids': Color(0xFFFFD54F),
    'Gifts': Color(0xFFFFAB40),
    'Donations': Color(0xFFFF6E40),

    // Others - Neutrals
    'Pet Care': Color(0xFFA1887F),
    'Repairs': Color(0xFF90A4AE),
    'Emergency': Color(0xFFF44336),
    'Matrimony': Color(0xFFE91E63),
    'Car Maintenance': Color(0xFF607D8B),
    'Miscellaneous': Color(0xFF9E9E9E),
  };

  static List<String> get allCategories => categoryIcons.keys.toList();

  static IconData getCategoryIcon(String category) {
    return categoryIcons[category] ?? Icons.attach_money;
  }

  static Color getCategoryColor(String category) {
    return categoryColors[category] ?? const Color(0xFF9E9E9E);
  }

  @override
  State<ExpenseList> createState() => _ExpenseListState();
}

class _ExpenseListState extends State<ExpenseList> with WidgetsBindingObserver {
  // Key to force rebuild of swipeable items when screen resumes
  int _resetKey = 0;
  // Track which item is currently open
  int? _openItemId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Reset all swipe states when app resumes
      setState(() {
        _resetKey++;
        _openItemId = null;
      });
    }
  }

  void _onItemOpened(int? itemId) {
    setState(() {
      _openItemId = itemId;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<ExpenseProvider, SettingsProvider>(
      builder: (context, expenseProvider, settingsProvider, child) {
        final expenses = expenseProvider.selectedDateExpenses;
        final isToday = expenseProvider.isToday;

        if (expenseProvider.isLoading) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        if (expenses.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.receipt_long,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  isToday ? 'No expenses today' : 'No expenses on this day',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isToday ? 'Tap the mic button to add one' : 'Select another date or add manually',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                ),
                const SizedBox(height: 24),
                TextButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AllExpensesScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.list_alt),
                  label: const Text('Show All Expenses'),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: expenses.length,
          itemBuilder: (context, index) {
            final expense = expenses[index];
            return _SwipeableExpenseItem(
              key: ValueKey('swipe_${expense.id}_$_resetKey'),
              expense: expense,
              formattedAmount: settingsProvider.formatAmount(expense.amount),
              currencySymbol: settingsProvider.currencySymbol,
              isOpen: _openItemId == expense.id,
              onOpenStateChanged: (isOpen) {
                _onItemOpened(isOpen ? expense.id : null);
              },
            );
          },
        );
      },
    );
  }
}

class _ExpenseListItem extends StatelessWidget {
  final Expense expense;
  final String formattedAmount;
  final String currencySymbol;

  const _ExpenseListItem({
    required this.expense,
    required this.formattedAmount,
    required this.currencySymbol,
  });

  @override
  Widget build(BuildContext context) {
    final dateTimeFormat = DateFormat('MMM d, yyyy');
    final categoryIcon = ExpenseList.getCategoryIcon(expense.category);
    final categoryColor = ExpenseList.getCategoryColor(expense.category);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: categoryColor.withOpacity(0.2),
              child: Icon(
                categoryIcon,
                color: categoryColor,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    expense.label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dateTimeFormat.format(expense.datetime),
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formattedAmount,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  expense.category,
                  style: TextStyle(
                    fontSize: 12,
                    color: categoryColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SwipeableExpenseItem extends StatefulWidget {
  final Expense expense;
  final String formattedAmount;
  final String currencySymbol;
  final bool isOpen;
  final ValueChanged<bool>? onOpenStateChanged;

  const _SwipeableExpenseItem({
    super.key,
    required this.expense,
    required this.formattedAmount,
    required this.currencySymbol,
    this.isOpen = false,
    this.onOpenStateChanged,
  });

  @override
  State<_SwipeableExpenseItem> createState() => _SwipeableExpenseItemState();
}

class _SwipeableExpenseItemState extends State<_SwipeableExpenseItem>
    with SingleTickerProviderStateMixin {
  static const double _actionButtonWidth = 64.0;
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  double _dragExtent = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(_SwipeableExpenseItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If this item should be closed (another item was opened)
    if (!widget.isOpen && oldWidget.isOpen) {
      _animateTo(0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    setState(() {
      final delta = details.primaryDelta ?? 0;

      // If currently open on one side and trying to drag opposite direction, first close
      if (_dragExtent < 0 && delta > 0) {
        // Was showing archive (left), dragging right - move toward closed
        _dragExtent = (_dragExtent + delta).clamp(-_actionButtonWidth, 0.0);
      } else if (_dragExtent > 0 && delta < 0) {
        // Was showing edit (right), dragging left - move toward closed
        _dragExtent = (_dragExtent + delta).clamp(0.0, _actionButtonWidth);
      } else if (_dragExtent == 0) {
        // Starting from closed - allow either direction
        _dragExtent = (_dragExtent + delta).clamp(-_actionButtonWidth, _actionButtonWidth);
      } else {
        // Continue in same direction
        _dragExtent = (_dragExtent + delta).clamp(-_actionButtonWidth, _actionButtonWidth);
      }
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    // Swipe left for archive
    if (_dragExtent < -_actionButtonWidth / 2 || (velocity < -500 && _dragExtent < 0)) {
      _animateTo(-_actionButtonWidth);
      widget.onOpenStateChanged?.call(true);
    }
    // Swipe right for edit
    else if (_dragExtent > _actionButtonWidth / 2 || (velocity > 500 && _dragExtent > 0)) {
      _animateTo(_actionButtonWidth);
      widget.onOpenStateChanged?.call(true);
    }
    // Snap back to closed
    else {
      _animateTo(0);
      widget.onOpenStateChanged?.call(false);
    }
  }

  void _animateTo(double target) {
    _slideAnimation = Tween<Offset>(
      begin: Offset(_dragExtent, 0),
      end: Offset(target, 0),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward(from: 0).then((_) {
      setState(() {
        _dragExtent = target;
      });
    });
  }

  void _closeSwipe() {
    _animateTo(0);
    widget.onOpenStateChanged?.call(false);
  }

  void _archiveExpense() {
    if (widget.expense.id == null) return;

    final expenseProvider = context.read<ExpenseProvider>();
    final expenseLabel = widget.expense.label;
    final expenseId = widget.expense.id!;

    expenseProvider.archiveExpense(expenseId);

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$expenseLabel archived'),
        duration: const Duration(seconds: 40),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            expenseProvider.restoreExpense(expenseId);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: _handleDragUpdate,
      onHorizontalDragEnd: _handleDragEnd,
      onTap: _closeSwipe,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final currentOffset = _controller.isAnimating
              ? _slideAnimation.value.dx
              : _dragExtent;

          return Stack(
            children: [
              // Edit button background (left side, revealed on swipe right)
              if (currentOffset > 0)
                Positioned.fill(
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: _actionButtonWidth,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            _closeSwipe();
                            _showEditDialog(context);
                          },
                          borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(12),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.edit,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              // Archive button background (right side, revealed on swipe left)
              if (currentOffset < 0)
                Positioned.fill(
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: _actionButtonWidth,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _archiveExpense,
                          borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(12),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.archive,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              // Foreground card
              Transform.translate(
                offset: Offset(currentOffset, 0),
                child: child,
              ),
            ],
          );
        },
        child: _ExpenseListItem(
          expense: widget.expense,
          formattedAmount: widget.formattedAmount,
          currencySymbol: widget.currencySymbol,
        ),
      ),
    );
  }

  void _showEditDialog(BuildContext context) {
    final labelController = TextEditingController(text: widget.expense.label);
    final amountController = TextEditingController(text: widget.expense.amount.toString());
    String selectedCategory = widget.expense.category;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: double.maxFinite,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Edit Expense',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: labelController,
                  decoration: const InputDecoration(
                    labelText: 'Label',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: amountController,
                  decoration: InputDecoration(
                    labelText: 'Amount',
                    border: const OutlineInputBorder(),
                    prefixText: '${widget.currencySymbol} ',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () => _showCategoryPicker(context, selectedCategory, (category) {
                    setState(() {
                      selectedCategory = category;
                    });
                  }),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.arrow_drop_down),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          ExpenseList.getCategoryIcon(selectedCategory),
                          color: ExpenseList.getCategoryColor(selectedCategory),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(selectedCategory),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
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
                        final label = labelController.text.trim();
                        final amount = double.tryParse(amountController.text) ?? 0;

                        if (label.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please enter a label')),
                          );
                          return;
                        }

                        final updatedExpense = widget.expense.copyWith(
                          label: label,
                          amount: amount,
                          category: selectedCategory,
                        );

                        this.context.read<ExpenseProvider>().updateExpense(updatedExpense);
                        Navigator.of(ctx).pop();
                      },
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCategoryPicker(BuildContext context, String currentCategory, Function(String) onSelect) {
    final searchController = TextEditingController();
    List<String> filteredCategories = ExpenseList.allCategories;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) => Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: 'Search category...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onChanged: (value) {
                    setState(() {
                      filteredCategories = ExpenseList.allCategories
                          .where((c) => c.toLowerCase().contains(value.toLowerCase()))
                          .toList();
                    });
                  },
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: filteredCategories.length,
                  itemBuilder: (context, index) {
                    final category = filteredCategories[index];
                    final isSelected = category == currentCategory;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: ExpenseList.getCategoryColor(category).withOpacity(0.2),
                        child: Icon(
                          ExpenseList.getCategoryIcon(category),
                          color: ExpenseList.getCategoryColor(category),
                          size: 20,
                        ),
                      ),
                      title: Text(
                        category,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? Theme.of(context).colorScheme.primary : null,
                        ),
                      ),
                      trailing: isSelected ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary) : null,
                      onTap: () {
                        onSelect(category);
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
