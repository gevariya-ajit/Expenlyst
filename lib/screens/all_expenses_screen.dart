import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/expense_list.dart';
import 'archived_expenses_screen.dart';

class AllExpensesScreen extends StatefulWidget {
  const AllExpensesScreen({super.key});

  @override
  State<AllExpensesScreen> createState() => _AllExpensesScreenState();
}

class _AllExpensesScreenState extends State<AllExpensesScreen> with WidgetsBindingObserver {
  List<Expense> _allExpenses = [];
  List<Expense> _filteredExpenses = [];
  bool _isLoading = true;

  // Search state
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Filter state
  DateTime? _startDate;
  DateTime? _endDate;
  String? _selectedCategory;

  // Key to force rebuild of swipeable items when screen resumes
  int _resetKey = 0;
  // Track which item is currently open
  int? _openItemId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Set default filter to current month (1st to today)
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, 1);
    _endDate = now;
    _loadAllExpenses();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
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

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
      _applyFilters();
    });
  }

  Future<void> _loadAllExpenses() async {
    setState(() => _isLoading = true);
    final provider = context.read<ExpenseProvider>();

    // Get all expenses from the database
    final allExpenses = await provider.getAllExpenses();

    setState(() {
      _allExpenses = allExpenses;
      _applyFilters();
      _isLoading = false;
    });
  }

  void _applyFilters() {
    _filteredExpenses = _allExpenses.where((expense) {
      // Search filter - supports multiple keywords separated by comma
      if (_searchQuery.isNotEmpty) {
        final keywords = _searchQuery
            .split(',')
            .map((k) => k.trim().toLowerCase())
            .where((k) => k.isNotEmpty)
            .toList();

        if (keywords.isNotEmpty) {
          final label = expense.label.toLowerCase();
          final category = expense.category.toLowerCase();

          // Check if any keyword matches label or category
          final hasMatch = keywords.any((keyword) =>
              label.contains(keyword) || category.contains(keyword));

          if (!hasMatch) {
            return false;
          }
        }
      }

      // Date range filter
      if (_startDate != null) {
        final startOfDay = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
        if (expense.datetime.isBefore(startOfDay)) {
          return false;
        }
      }
      if (_endDate != null) {
        final endOfDay = DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
        if (expense.datetime.isAfter(endOfDay)) {
          return false;
        }
      }

      // Category filter
      if (_selectedCategory != null && expense.category != _selectedCategory) {
        return false;
      }

      return true;
    }).toList();
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _startDate = null;
      _endDate = null;
      _selectedCategory = null;
      _applyFilters();
    });
  }

  bool get _hasActiveFilters =>
      _startDate != null || _endDate != null || _selectedCategory != null;

  bool get _hasSearchOrFilters =>
      _searchQuery.isNotEmpty || _hasActiveFilters;

  String _getSearchChipLabel() {
    final keywords = _searchQuery
        .split(',')
        .map((k) => k.trim())
        .where((k) => k.isNotEmpty)
        .toList();

    if (keywords.length == 1) {
      return '"${keywords[0]}"';
    } else if (keywords.length == 2) {
      return '"${keywords[0]}", "${keywords[1]}"';
    } else {
      return '"${keywords[0]}" +${keywords.length - 1} more';
    }
  }

  double get _filteredTotal =>
      _filteredExpenses.fold(0.0, (sum, e) => sum + e.amount);

  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Filter Expenses',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_hasActiveFilters)
                        TextButton(
                          onPressed: () {
                            setSheetState(() {
                              _startDate = null;
                              _endDate = null;
                              _selectedCategory = null;
                            });
                          },
                          child: const Text('Clear All'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Date Range Section
                  const Text(
                    'Date Range',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: _startDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now(),
                            );
                            if (date != null) {
                              setSheetState(() => _startDate = date);
                            }
                          },
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'From',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              suffixIcon: _startDate != null
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 18),
                                      onPressed: () {
                                        setSheetState(() => _startDate = null);
                                      },
                                    )
                                  : const Icon(Icons.calendar_today, size: 18),
                            ),
                            child: Text(
                              _startDate != null
                                  ? DateFormat('MMM d, yyyy').format(_startDate!)
                                  : 'Select date',
                              style: TextStyle(
                                color: _startDate != null
                                    ? Colors.black87
                                    : Colors.grey[600],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: _endDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now(),
                            );
                            if (date != null) {
                              setSheetState(() => _endDate = date);
                            }
                          },
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'To',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              suffixIcon: _endDate != null
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 18),
                                      onPressed: () {
                                        setSheetState(() => _endDate = null);
                                      },
                                    )
                                  : const Icon(Icons.calendar_today, size: 18),
                            ),
                            child: Text(
                              _endDate != null
                                  ? DateFormat('MMM d, yyyy').format(_endDate!)
                                  : 'Select date',
                              style: TextStyle(
                                color: _endDate != null
                                    ? Colors.black87
                                    : Colors.grey[600],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Category Section
                  const Text(
                    'Category',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () => _showCategoryFilterPicker(context, (category) {
                      setSheetState(() => _selectedCategory = category);
                    }),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Category',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        suffixIcon: _selectedCategory != null
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  setSheetState(() => _selectedCategory = null);
                                },
                              )
                            : const Icon(Icons.arrow_drop_down),
                      ),
                      child: _selectedCategory != null
                          ? Row(
                              children: [
                                Icon(
                                  ExpenseList.getCategoryIcon(_selectedCategory!),
                                  color: ExpenseList.getCategoryColor(_selectedCategory!),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(_selectedCategory!),
                              ],
                            )
                          : Text(
                              'All Categories',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Apply Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _applyFilters();
                        });
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Apply Filters',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showCategoryFilterPicker(BuildContext context, Function(String?) onSelect) {
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
                    final isSelected = category == _selectedCategory;
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
                      trailing: isSelected
                          ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                          : null,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('All Expenses'),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.filter_list),
                onPressed: _showFilterBottomSheet,
                tooltip: 'Filter',
              ),
              if (_hasActiveFilters)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'archived') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ArchivedExpensesScreen(),
                  ),
                ).then((_) => _loadAllExpenses());
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'archived',
                child: Row(
                  children: [
                    Icon(Icons.archive_outlined, size: 20, color: Colors.orange[700]),
                    const SizedBox(width: 8),
                    const Text('Archived'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settingsProvider, child) {
          if (_isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return Column(
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search expenses (use , for multiple)...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2,
                      ),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ),

              // Active filters and total
              if (_hasSearchOrFilters || _filteredExpenses.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Search and filter chips
                      if (_hasSearchOrFilters)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (_searchQuery.isNotEmpty)
                              Chip(
                                avatar: const Icon(Icons.search, size: 16),
                                label: Text(
                                  _getSearchChipLabel(),
                                  style: const TextStyle(fontSize: 12),
                                ),
                                deleteIcon: const Icon(Icons.close, size: 16),
                                onDeleted: () {
                                  _searchController.clear();
                                },
                                visualDensity: VisualDensity.compact,
                              ),
                            if (_startDate != null || _endDate != null)
                              Chip(
                                label: Text(
                                  _startDate != null && _endDate != null
                                      ? '${DateFormat('MMM d').format(_startDate!)} - ${DateFormat('MMM d').format(_endDate!)}'
                                      : _startDate != null
                                          ? 'From ${DateFormat('MMM d').format(_startDate!)}'
                                          : 'Until ${DateFormat('MMM d').format(_endDate!)}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                deleteIcon: const Icon(Icons.close, size: 16),
                                onDeleted: () {
                                  setState(() {
                                    _startDate = null;
                                    _endDate = null;
                                    _applyFilters();
                                  });
                                },
                                visualDensity: VisualDensity.compact,
                              ),
                            if (_selectedCategory != null)
                              Chip(
                                avatar: Icon(
                                  ExpenseList.getCategoryIcon(_selectedCategory!),
                                  size: 16,
                                  color: ExpenseList.getCategoryColor(_selectedCategory!),
                                ),
                                label: Text(
                                  _selectedCategory!,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                deleteIcon: const Icon(Icons.close, size: 16),
                                onDeleted: () {
                                  setState(() {
                                    _selectedCategory = null;
                                    _applyFilters();
                                  });
                                },
                                visualDensity: VisualDensity.compact,
                              ),
                          ],
                        ),
                      if (_hasSearchOrFilters) const SizedBox(height: 8),
                      // Total row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${_filteredExpenses.length} expense${_filteredExpenses.length != 1 ? 's' : ''}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                            ),
                          ),
                          Text(
                            'Total: ${settingsProvider.formatAmount(_filteredTotal)}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

              // Expense list
              Expanded(
                child: _filteredExpenses.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _hasSearchOrFilters ? Icons.search_off : Icons.receipt_long,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isNotEmpty
                                  ? 'No expenses match your search'
                                  : _hasActiveFilters
                                      ? 'No expenses match your filters'
                                      : 'No expenses yet',
                              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                              textAlign: TextAlign.center,
                            ),
                            if (_hasSearchOrFilters) ...[
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: _clearFilters,
                                child: Text(_searchQuery.isNotEmpty && _hasActiveFilters
                                    ? 'Clear Search & Filters'
                                    : _searchQuery.isNotEmpty
                                        ? 'Clear Search'
                                        : 'Clear Filters'),
                              ),
                            ],
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _getGroupedExpenses().length,
                        itemBuilder: (context, index) {
                          final groupedExpenses = _getGroupedExpenses();
                          final dateKey = groupedExpenses.keys.elementAt(index);
                          final expenses = groupedExpenses[dateKey]!;
                          final dayTotal = expenses.fold(0.0, (sum, e) => sum + e.amount);

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      dateKey,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                    Text(
                                      settingsProvider.formatAmount(dayTotal),
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ...expenses.map((expense) => _buildExpenseItem(
                                context,
                                expense,
                                settingsProvider,
                              )),
                              const SizedBox(height: 8),
                            ],
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Map<String, List<Expense>> _getGroupedExpenses() {
    final groupedExpenses = <String, List<Expense>>{};
    for (final expense in _filteredExpenses) {
      final dateKey = DateFormat('EEEE, MMM d, yyyy').format(expense.datetime);
      groupedExpenses.putIfAbsent(dateKey, () => []).add(expense);
    }
    return groupedExpenses;
  }

  Widget _buildExpenseItem(
    BuildContext context,
    Expense expense,
    SettingsProvider settingsProvider,
  ) {
    return _SwipeToArchiveItem(
      key: ValueKey('all_swipe_${expense.id}_$_resetKey'),
      expense: expense,
      settingsProvider: settingsProvider,
      isOpen: _openItemId == expense.id,
      onOpenStateChanged: (isOpen) {
        _onItemOpened(isOpen ? expense.id : null);
      },
      onArchive: () {
        final expenseProvider = context.read<ExpenseProvider>();
        final expenseLabel = expense.label;
        final expenseId = expense.id!;

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
                _loadAllExpenses();
              },
            ),
          ),
        );

        _loadAllExpenses();
      },
      onExpenseUpdated: _loadAllExpenses,
    );
  }
}

class _SwipeToArchiveItem extends StatefulWidget {
  final Expense expense;
  final SettingsProvider settingsProvider;
  final VoidCallback onArchive;
  final bool isOpen;
  final ValueChanged<bool>? onOpenStateChanged;
  final VoidCallback onExpenseUpdated;

  const _SwipeToArchiveItem({
    super.key,
    required this.expense,
    required this.settingsProvider,
    required this.onArchive,
    required this.onExpenseUpdated,
    this.isOpen = false,
    this.onOpenStateChanged,
  });

  @override
  State<_SwipeToArchiveItem> createState() => _SwipeToArchiveItemState();
}

class _SwipeToArchiveItemState extends State<_SwipeToArchiveItem>
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
  void didUpdateWidget(_SwipeToArchiveItem oldWidget) {
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
                    prefixText: '${widget.settingsProvider.currencySymbol} ',
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
                      onPressed: () async {
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

                        await this.context.read<ExpenseProvider>().updateExpense(updatedExpense);
                        Navigator.of(ctx).pop();
                        widget.onExpenseUpdated();
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

  @override
  Widget build(BuildContext context) {
    final categoryIcon = ExpenseList.getCategoryIcon(widget.expense.category);
    final categoryColor = ExpenseList.getCategoryColor(widget.expense.category);

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
                          onTap: widget.onArchive,
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
        child: Card(
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
                  child: Text(
                    widget.expense.label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      widget.settingsProvider.formatAmount(widget.expense.amount),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.expense.category,
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
        ),
      ),
    );
  }
}
