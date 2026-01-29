import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/expense_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/sync_provider.dart';
import '../models/expense.dart';
import '../widgets/summary_card.dart';
import '../widgets/expense_list.dart';
import '../widgets/voice_input_button.dart';
import '../widgets/custom_bottom_nav_bar.dart';
import 'settings_screen.dart';
import 'all_expenses_screen.dart';
import 'subscriptions_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<VoiceInputButtonState> _voiceInputKey = GlobalKey<VoiceInputButtonState>();

  @override
  void initState() {
    super.initState();
    // Load expenses when screen initializes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ExpenseProvider>().loadExpenses();
    });
  }

  Future<void> _showAddExpenseDialog() async {
    final labelController = TextEditingController();
    final amountController = TextEditingController();
    String selectedCategory = 'Miscellaneous';
    final expenseProvider = context.read<ExpenseProvider>();
    DateTime selectedDate = expenseProvider.selectedDate;
    TimeOfDay selectedTime = expenseProvider.isToday ? TimeOfDay.now() : const TimeOfDay(hour: 12, minute: 0);

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Add Expense'),
            content: SingleChildScrollView(
              child: SizedBox(
                width: MediaQuery.of(context).size.width * 0.8,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: labelController,
                      decoration: const InputDecoration(
                        labelText: 'Label',
                        hintText: 'e.g., Coffee, Uber, Groceries',
                        border: OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: amountController,
                      decoration: InputDecoration(
                        labelText: 'Amount',
                        hintText: '0.00',
                        border: const OutlineInputBorder(),
                        prefixText: '${context.read<SettingsProvider>().currencySymbol} ',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 16),
                    // Category selector
                    InkWell(
                      onTap: () async {
                        final category = await _showCategoryPicker(selectedCategory);
                        if (category != null) {
                          setDialogState(() => selectedCategory = category);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Category',
                          border: OutlineInputBorder(),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              ExpenseList.categoryIcons[selectedCategory] ?? Icons.category,
                              color: ExpenseList.categoryColors[selectedCategory] ?? Colors.grey,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(selectedCategory)),
                            const Icon(Icons.arrow_drop_down),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Date picker
                    InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (date != null) {
                          setDialogState(() => selectedDate = date);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Date',
                          border: OutlineInputBorder(),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today, size: 20),
                            const SizedBox(width: 8),
                            Text(DateFormat('EEE, MMM d, yyyy').format(selectedDate)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Time picker
                    InkWell(
                      onTap: () async {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: selectedTime,
                        );
                        if (time != null) {
                          setDialogState(() => selectedTime = time);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Time',
                          border: OutlineInputBorder(),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.access_time, size: 20),
                            const SizedBox(width: 8),
                            Text(selectedTime.format(context)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final label = labelController.text.trim();
                  final amount = double.tryParse(amountController.text.trim());
                  if (label.isNotEmpty && amount != null && amount > 0) {
                    Navigator.pop(ctx, {
                      'label': label,
                      'amount': amount,
                      'category': selectedCategory,
                      'date': selectedDate,
                      'time': selectedTime,
                    });
                  }
                },
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );

    if (result != null) {
      final datetime = DateTime(
        result['date'].year,
        result['date'].month,
        result['date'].day,
        result['time'].hour,
        result['time'].minute,
      );

      final expense = Expense(
        label: result['label'],
        amount: result['amount'],
        category: result['category'],
        datetime: datetime,
      );

      await context.read<ExpenseProvider>().addExpense(expense);
    }
  }

  Future<String?> _showCategoryPicker(String currentCategory) async {
    final searchController = TextEditingController();
    final categories = ExpenseList.categoryIcons.keys.toList()..sort();

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final filteredCategories = categories
              .where((c) => c.toLowerCase().contains(searchController.text.toLowerCase()))
              .toList();

          return DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.5,
            maxChildSize: 0.9,
            expand: false,
            builder: (context, scrollController) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: 'Search category...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onChanged: (_) => setSheetState(() {}),
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
                        leading: Icon(
                          ExpenseList.categoryIcons[category] ?? Icons.category,
                          color: ExpenseList.categoryColors[category] ?? Colors.grey,
                        ),
                        title: Text(category),
                        trailing: isSelected ? const Icon(Icons.check, color: Colors.green) : null,
                        onTap: () => Navigator.pop(ctx, category),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _selectDate() async {
    final expenseProvider = context.read<ExpenseProvider>();
    final date = await showDatePicker(
      context: context,
      initialDate: expenseProvider.selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (date != null) {
      await expenseProvider.setSelectedDate(date);
    }
  }

  void _goToToday() {
    context.read<ExpenseProvider>().setSelectedDate(DateTime.now());
  }

  void _navigateToSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SettingsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;

        // Check if voice recording is active
        final voiceState = _voiceInputKey.currentState;
        if (voiceState != null && voiceState.isListening) {
          // Stop recording instead of closing the app
          voiceState.stopListening();
        } else {
          // Allow normal back navigation (close app)
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: GestureDetector(
            onTap: _navigateToSettings,
            child: Consumer<SyncProvider>(
              builder: (context, syncProvider, child) {
                if (syncProvider.isSignedIn) {
                  // Show profile picture or initials
                  if (syncProvider.userPhotoUrl != null) {
                    return CircleAvatar(
                      backgroundImage: NetworkImage(syncProvider.userPhotoUrl!),
                      backgroundColor: Colors.white24,
                    );
                  } else {
                    return CircleAvatar(
                      backgroundColor: Colors.white24,
                      child: Text(
                        syncProvider.userInitials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    );
                  }
                } else {
                  // Show default account icon when not signed in
                  return const CircleAvatar(
                    backgroundColor: Colors.white24,
                    child: Icon(
                      Icons.account_circle,
                      color: Colors.white,
                      size: 24,
                    ),
                  );
                }
              },
            ),
          ),
        ),
        title: const Text('Expenlyst'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddExpenseDialog,
            tooltip: 'Add expense manually',
          ),
        ],
      ),
      body: Stack(
        children: [
          // Main content
          Consumer<ExpenseProvider>(
            builder: (context, expenseProvider, child) {
              final isToday = expenseProvider.isToday;
              final selectedDate = expenseProvider.selectedDate;

              // Format header text
              String headerText;
              if (isToday) {
                headerText = "Today's Expenses";
              } else {
                headerText = DateFormat('EEE, MMM d').format(selectedDate);
              }

              return Column(
                children: [
                  const SummaryCard(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            headerText,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[800],
                            ),
                          ),
                        ),
                        if (!isToday)
                          TextButton.icon(
                            onPressed: _goToToday,
                            icon: const Icon(Icons.today, size: 18),
                            label: const Text('Today'),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        IconButton(
                          icon: const Icon(Icons.calendar_month),
                          onPressed: _selectDate,
                          tooltip: 'Select date',
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Expanded(
                    child: ExpenseList(),
                  ),
                  // Bottom padding for nav bar
                  const SizedBox(height: 86),
                ],
              );
            },
          ),
          // Bottom navigation bar overlay
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: CustomBottomNavBar(
              onExpensesTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AllExpensesScreen(),
                  ),
                );
              },
              onSubscriptionsTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SubscriptionsScreen(),
                  ),
                );
              },
              centerButton: VoiceInputButton(key: _voiceInputKey),
            ),
          ),
        ],
      ),
    ),
    );
  }
}
