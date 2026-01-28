import 'dart:math' show sin;

import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../providers/settings_provider.dart';
import '../services/database_service.dart';

class VoiceInputButton extends StatefulWidget {
  const VoiceInputButton({super.key});

  @override
  State<VoiceInputButton> createState() => VoiceInputButtonState();
}

class VoiceInputButtonState extends State<VoiceInputButton>
    with SingleTickerProviderStateMixin {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;

  /// Returns true if currently listening for voice input
  bool get isListening => _isListening;

  /// Stops the current voice recording session
  Future<void> stopListening() => _stopListening();
  bool _isInitialized = false;
  String _lastWords = '';
  String _stableWords = ''; // Track stable recognized text
  int _stableWordCount = 0; // Count of words that haven't changed
  DateTime? _lastChangeTime; // When text last changed
  bool _isProcessing = false; // Prevent double processing

  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  // Comprehensive category keywords mapping
  static const Map<String, List<String>> _categoryKeywords = {
    // Household
    'Household': ['household', 'home', 'house'],
    'Rent': ['rent', 'rental'],
    'Maintenance': ['maintenance', 'repair', 'plumber', 'electrician', 'carpenter'],
    'Electricity': ['electricity', 'electric', 'power', 'light bill'],
    'Water': ['water', 'water bill'],
    'Gas': ['gas', 'cylinder', 'lpg', 'png'],
    'Internet': ['internet', 'wifi', 'wi-fi', 'broadband', 'fiber'],
    'Mobile Recharge': ['mobile', 'recharge', 'phone bill', 'airtel', 'jio', 'vi', 'bsnl'],
    'OTT Subscriptions': ['netflix', 'amazon prime', 'prime', 'hotstar', 'disney', 'spotify', 'youtube premium', 'ott', 'subscription'],

    // Food & Dining
    'Groceries': ['groceries', 'grocery', 'kirana', 'supermarket', 'bigbasket', 'blinkit', 'zepto', 'instamart'],
    'Vegetables & Fruits': ['vegetables', 'veggies', 'fruits', 'fruit', 'sabzi', 'produce'],
    'Milk & Dairy': ['milk', 'dairy', 'curd', 'paneer', 'cheese', 'butter', 'ghee', 'yogurt'],
    'Snacks': ['snacks', 'snack', 'chips', 'biscuits', 'cookies', 'namkeen'],
    'Restaurants': ['restaurant', 'cafe', 'dine', 'dining', 'lunch', 'dinner', 'breakfast', 'brunch', 'food court'],
    'Food Orders': ['swiggy', 'zomato', 'food order', 'delivery', 'takeaway', 'takeout', 'pizza', 'burger', 'biryani'],

    // Transportation
    'Fuel': ['fuel', 'petrol', 'diesel', 'cng', 'ev charging', 'charging'],
    'Public Transport': ['metro', 'bus', 'train', 'railway', 'local', 'public transport'],
    'Cab': ['cab', 'taxi', 'uber', 'ola', 'rapido', 'auto', 'rickshaw'],
    'Vehicle Maintenance': ['service', 'vehicle service', 'car service', 'bike service', 'tyre', 'tire', 'oil change'],
    'Parking': ['parking', 'valet'],
    'Toll': ['toll', 'fastag'],
    'Car EMI': ['car emi', 'vehicle emi', 'bike emi', 'car loan'],

    // Shopping
    'Clothing': ['clothing', 'clothes', 'shirt', 'pants', 'dress', 'jeans', 'tshirt', 't-shirt', 'kurti', 'saree'],
    'Footwear': ['footwear', 'shoes', 'sandals', 'slippers', 'sneakers', 'boots'],
    'Accessories': ['accessories', 'watch', 'belt', 'wallet', 'bag', 'purse', 'sunglasses'],
    'Online Shopping': ['amazon', 'flipkart', 'myntra', 'ajio', 'meesho', 'online shopping', 'nykaa'],
    'Electronics': ['electronics', 'phone', 'laptop', 'tablet', 'headphones', 'earphones', 'charger', 'cable', 'gadget'],
    'Home Essentials': ['home essentials', 'cleaning', 'detergent', 'soap', 'toiletries', 'tissue'],

    // Health & Medical
    'Doctor': ['doctor', 'clinic', 'hospital', 'consultation', 'checkup', 'health checkup', 'test', 'lab'],
    'Medicines': ['medicine', 'medicines', 'pharmacy', 'medical', 'tablet', 'pills', 'netmeds', 'pharmeasy', '1mg'],
    'Insurance Premium': ['insurance', 'premium', 'health insurance', 'life insurance', 'policy'],
    'Gym': ['gym', 'fitness', 'yoga', 'workout', 'exercise', 'cult', 'cult fit'],

    // Education
    'School Fees': ['school', 'college', 'university', 'fees', 'tuition', 'admission'],
    'Coaching': ['coaching', 'tuition', 'classes', 'tutorial'],
    'Online Courses': ['course', 'udemy', 'coursera', 'skillshare', 'masterclass', 'online course', 'learning'],
    'Books & Stationery': ['books', 'book', 'stationery', 'notebook', 'pen', 'pencil'],

    // Entertainment & Leisure
    'Movies': ['movie', 'movies', 'cinema', 'theatre', 'theater', 'bookmyshow', 'pvr', 'inox'],
    'Games': ['game', 'games', 'gaming', 'playstation', 'xbox', 'steam'],
    'Travel': ['travel', 'trip', 'vacation', 'holiday', 'flight', 'hotel', 'booking', 'makemytrip', 'goibibo', 'oyo'],
    'Events': ['event', 'concert', 'show', 'ticket', 'tickets', 'match'],
    'Hobbies': ['hobby', 'hobbies', 'craft', 'art', 'music', 'sports', 'photography'],

    // Work & Business
    'Office Supplies': ['office', 'supplies', 'printer', 'paper', 'ink'],
    'Software': ['software', 'app', 'tool', 'saas', 'license'],
    'Work Travel': ['work travel', 'business trip', 'client visit'],
    'Client Expenses': ['client', 'business lunch', 'business dinner'],

    // Financial
    'Loan EMI': ['emi', 'loan', 'home loan', 'personal loan'],
    'Credit Card': ['credit card', 'credit card payment', 'card payment', 'cc payment'],
    'Investments': ['investment', 'mutual fund', 'sip', 'stocks', 'shares', 'fd', 'fixed deposit'],
    'Taxes': ['tax', 'taxes', 'income tax', 'gst'],
    'Savings': ['savings', 'ppf', 'nps', 'rd'],

    // Personal & Family
    'Personal Care': ['personal care', 'cosmetics', 'makeup', 'skincare', 'beauty'],
    'Salon': ['salon', 'haircut', 'spa', 'grooming', 'parlour', 'parlor', 'barber'],
    'Kids': ['kids', 'children', 'baby', 'toys', 'diapers', 'school supplies'],
    'Gifts': ['gift', 'gifts', 'present', 'birthday gift', 'wedding gift'],
    'Donations': ['donation', 'charity', 'temple', 'church', 'mosque', 'religious'],

    // Others
    'Pet Care': ['pet', 'dog', 'cat', 'vet', 'pet food'],
    'Repairs': ['repair', 'fix', 'broken'],
    'Emergency': ['emergency', 'urgent'],
    'Matrimony': ['matrimony', 'shaadi', 'wedding', 'marriage', 'jeevansathi', 'bharatmatrimony'],
    'Car Maintenance': ['car', 'car maintenance', 'car wash', 'car service', 'mechanic', 'garage', 'denting', 'painting'],
    'Miscellaneous': ['misc', 'miscellaneous', 'other'],
  };

  // Common food/beverage items for smart detection
  static const List<String> _foodItems = [
    'coffee', 'tea', 'chai', 'juice', 'smoothie', 'shake',
    'sandwich', 'burger', 'pizza', 'pasta', 'noodles', 'momos',
    'dosa', 'idli', 'vada', 'samosa', 'pakora', 'chaat',
    'rice', 'roti', 'naan', 'paratha', 'thali', 'meal',
    'ice cream', 'dessert', 'cake', 'pastry', 'sweet',
    'chicken', 'mutton', 'fish', 'egg', 'paneer',
  ];

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _setupAnimations();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _opacityAnimation = Tween<double>(begin: 0.7, end: 0.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _animationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _animationController.reset();
        if (_isListening) {
          _animationController.forward();
        }
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    _isInitialized = await _speech.initialize(
      onError: (error) {
        debugPrint('Speech recognition error: $error');
        setState(() {
          _isListening = false;
        });
      },
      onStatus: (status) {
        debugPrint('Speech recognition status: $status');
        if (status == 'done' || status == 'notListening') {
          setState(() {
            _isListening = false;
          });
        }
      },
    );
    setState(() {});
  }

  Future<void> _startListening() async {
    if (!_isInitialized) {
      _showSnackBar('Speech recognition not available');
      return;
    }

    setState(() {
      _isListening = true;
      _lastWords = '';
      _stableWords = '';
      _stableWordCount = 0;
      _lastChangeTime = null;
      _isProcessing = false;
    });

    _animationController.forward();

    // Get selected locale from settings
    final settingsProvider = context.read<SettingsProvider>();
    final localeId = settingsProvider.speechLocale;

    await _speech.listen(
      onResult: (result) {
        if (_isProcessing) return; // Skip if already processing

        final newWords = result.recognizedWords;
        setState(() {
          _lastWords = newWords;
        });

        // Track text stability for smart auto-stop
        if (newWords != _stableWords) {
          _stableWords = newWords;
          _lastChangeTime = DateTime.now();
          _stableWordCount = 0;
        } else {
          _stableWordCount++;
        }

        // Auto-stop conditions:
        // 1. Final result from speech recognizer
        // 2. Text has been stable AND contains a valid expense pattern (has number)
        if (result.finalResult) {
          _finishListening(newWords);
        } else if (_shouldAutoStop(newWords)) {
          _finishListening(newWords);
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 4),
      localeId: localeId,
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        listenMode: stt.ListenMode.dictation,
      ),
    );
  }

  /// Check if we should auto-stop based on speech pattern
  bool _shouldAutoStop(String text) {
    if (text.isEmpty || _lastChangeTime == null) return false;

    // Check if text contains a number (valid expense input)
    final hasNumber = RegExp(r'\d+').hasMatch(text);
    if (!hasNumber) return false;

    // Check if text has been stable for at least 2 seconds
    final timeSinceChange = DateTime.now().difference(_lastChangeTime!);
    if (timeSinceChange.inMilliseconds < 2000) return false;

    // Additional check: stable word count indicates no changes
    return _stableWordCount >= 2;
  }

  /// Finish listening and process the input
  Future<void> _finishListening(String text) async {
    if (_isProcessing) return;
    _isProcessing = true;

    await _speech.stop();
    _animationController.stop();
    _animationController.reset();

    setState(() {
      _isListening = false;
    });

    // Small delay to ensure we have final text
    await Future.delayed(const Duration(milliseconds: 100));

    _processVoiceInput(text);
  }

  Future<void> _stopListening() async {
    if (_isProcessing) return;

    // If we have text, process it; otherwise just cancel
    if (_lastWords.isNotEmpty) {
      await _finishListening(_lastWords);
    } else {
      await _speech.stop();
      _animationController.stop();
      _animationController.reset();
      setState(() {
        _isListening = false;
        _isProcessing = false;
      });
    }
  }

  // Command phrases for archiving last expense
  static const List<String> _archiveLastCommands = [
    // Remove variations
    'remove last', 'remove last item', 'remove last expense', 'remove last entry',
    'remove the last', 'remove the last item', 'remove the last expense', 'remove the last entry',
    'remove previous', 'remove previous item', 'remove previous expense',
    // Delete variations
    'delete last', 'delete last item', 'delete last expense', 'delete last entry',
    'delete the last', 'delete the last item', 'delete the last expense', 'delete the last entry',
    'delete previous', 'delete previous item', 'delete previous expense',
    // Drop variations
    'drop last', 'drop last item', 'drop last expense', 'drop last entry',
    'drop the last', 'drop the last item', 'drop the last expense', 'drop the last entry',
    // Cancel variations
    'cancel last', 'cancel last item', 'cancel last expense', 'cancel last entry',
    'cancel the last', 'cancel the last item', 'cancel the last expense',
    // Undo variations
    'undo', 'undo last', 'undo last item', 'undo last expense', 'undo that',
    // Short forms
    'remove it', 'delete it', 'drop it', 'cancel it', 'take it back',
    'never mind', 'nevermind', 'scratch that', 'forget it', 'forget that',
  ];

  /// Check if text is a command to archive last expense (with fuzzy matching)
  bool _isArchiveLastCommand(String text) {
    final lowerText = text.toLowerCase().trim();

    // First check exact match or contains
    if (_archiveLastCommands.any((cmd) => lowerText == cmd || lowerText.contains(cmd))) {
      return true;
    }

    // Then check fuzzy match for minor errors
    const double threshold = 0.75;
    for (final cmd in _archiveLastCommands) {
      if (_similarity(lowerText, cmd) >= threshold) {
        return true;
      }
      // Also check if any part of the text matches the command
      final words = lowerText.split(RegExp(r'\s+'));
      if (words.length >= 2) {
        // Check pairs of consecutive words
        for (int i = 0; i < words.length - 1; i++) {
          final phrase = '${words[i]} ${words[i + 1]}';
          if (_similarity(phrase, cmd) >= threshold) {
            return true;
          }
        }
      }
    }

    return false;
  }

  /// Archive the last expense
  Future<void> _archiveLastExpense() async {
    final expenseProvider = context.read<ExpenseProvider>();
    final expenses = expenseProvider.selectedDateExpenses;

    if (expenses.isEmpty) {
      _showSnackBar('No expenses to remove');
      return;
    }

    // Get the most recent expense (first in list since sorted DESC)
    final lastExpense = expenses.first;
    final expenseId = lastExpense.id!;

    await expenseProvider.archiveExpense(expenseId);

    _showSnackBarWithUndo(
      'Removed: ${lastExpense.label} - ${lastExpense.amount.toStringAsFixed(0)}',
      expenseId,
    );
  }

  /// Show snackbar with undo action for restoring archived expense
  void _showSnackBarWithUndo(String message, int expenseId) {
    // Capture provider reference before showing snackbar
    final expenseProvider = context.read<ExpenseProvider>();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 10),
        action: SnackBarAction(
          label: 'Undo',
          textColor: Colors.yellow,
          onPressed: () async {
            debugPrint('Restoring expense with ID: $expenseId');
            await expenseProvider.restoreExpense(expenseId);
            _showSnackBar('Restored');
          },
        ),
      ),
    );
  }

  Future<void> _processVoiceInput(String text) async {
    if (text.isEmpty) {
      _showSnackBar('No speech detected');
      return;
    }

    // Check for commands first
    if (_isArchiveLastCommand(text)) {
      await _archiveLastExpense();
      return;
    }

    final parsed = _parseExpense(text);
    String label = parsed['label']!;

    // Try smart label matching
    final matchedLabel = await _findBestMatchingLabel(label);
    final wasSmartMatched = matchedLabel != null;
    if (wasSmartMatched) {
      label = matchedLabel;
    }

    // Check if same label exists in database to auto-capture category
    final expenseProvider = context.read<ExpenseProvider>();
    final existingCategory = await expenseProvider.getCategoryByLabel(label);
    final category = existingCategory ?? parsed['category']!;

    // Use selected date with current time
    final selectedDate = expenseProvider.selectedDate;
    final now = DateTime.now();
    final expenseDateTime = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      now.hour,
      now.minute,
      now.second,
    );

    final expense = Expense(
      label: label,
      datetime: expenseDateTime,
      category: category,
      amount: double.parse(parsed['amount']!),
    );

    expenseProvider.addExpense(expense);

    // Build status message
    String statusMsg = 'Added: ${expense.label} - ${parsed['amount']}';
    if (wasSmartMatched) {
      statusMsg += ' (smart match)';
    }
    _showSnackBar(statusMsg);
  }

  // Words that indicate category but should not be part of the label
  static const List<String> _categoryIndicatorWords = [
    // Payment related
    'bill', 'bills', 'payment', 'payments', 'paid', 'pay',
    'recharge', 'recharged', 'top', 'up', 'topup',
    // Order related
    'order', 'ordered', 'delivery', 'delivered',
    // Purchase related
    'bought', 'buy', 'purchase', 'purchased', 'shopping',
    // Service related
    'service', 'serviced', 'repair', 'repaired', 'maintenance',
    // Travel related
    'ride', 'trip', 'travel', 'fare', 'booking', 'booked',
    // Food related
    'food', 'meal', 'lunch', 'dinner', 'breakfast', 'snack',
    // Common suffixes
    'expense', 'expenses', 'cost', 'charge', 'charges', 'fee', 'fees',
    // Prepositions often used
    'for', 'from', 'to', 'at', 'on', 'in', 'the', 'a', 'an',
  ];

  Map<String, String> _parseExpense(String text) {
    final lowerText = text.toLowerCase();
    final words = lowerText.split(RegExp(r'\s+'));

    // Find amount (number with optional decimal)
    String? amount;
    int amountIndex = -1;

    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      // Check for number (including comma-separated like 1,000)
      final cleanWord = word.replaceAll(',', '');
      final numberMatch = RegExp(r'^(\d+\.?\d*)$').firstMatch(cleanWord);
      if (numberMatch != null) {
        amount = numberMatch.group(1);
        amountIndex = i;
        break;
      }
    }

    // Detect category FIRST based on the full text (before removing words)
    String category = _detectCategory(lowerText, '');

    // Create a mutable list for processing
    List<String> labelWords = List.from(words);

    // Remove amount and currency words from label
    if (amountIndex != -1) {
      labelWords.removeAt(amountIndex);
    }

    // Remove currency words
    labelWords.removeWhere((w) =>
      w == 'dollars' || w == 'dollar' || w == 'rupees' || w == 'rupee' ||
      w == 'rs' || w == 'inr' || w == 'usd' || w == '\$' || w == 'rs.');

    // Remove category indicator words from label
    labelWords.removeWhere((w) => _categoryIndicatorWords.contains(w));

    // Build label from remaining words
    String label = labelWords.where((w) => w.isNotEmpty).join(' ').trim();

    // If no label, use "Expense"
    if (label.isEmpty) {
      label = 'Expense';
    }

    // Capitalize first letter of each word
    label = _capitalizeWords(label);

    // If category wasn't detected from keywords, try detecting from the cleaned label
    if (category == 'Miscellaneous') {
      category = _detectCategory(lowerText, label.toLowerCase());
    }

    // If no amount found, default to 0 (user can edit later)
    amount ??= '0';

    return {
      'label': label,
      'amount': amount,
      'category': category,
    };
  }

  String _capitalizeWords(String text) {
    if (text.isEmpty) return text;
    return text.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
  }

  String _detectCategory(String fullText, String label) {
    // First check for explicit category keywords in the full text
    for (final entry in _categoryKeywords.entries) {
      for (final keyword in entry.value) {
        if (fullText.contains(keyword)) {
          return entry.key;
        }
      }
    }

    // Check for common food items
    for (final item in _foodItems) {
      if (label.contains(item)) {
        // Determine if it's restaurant/cafe food or delivery
        if (fullText.contains('swiggy') || fullText.contains('zomato') ||
            fullText.contains('delivery') || fullText.contains('order')) {
          return 'Food Orders';
        }
        return 'Restaurants';
      }
    }

    // Smart detection based on common patterns
    if (_containsAny(fullText, ['bought', 'purchase', 'shopping', 'ordered'])) {
      if (_containsAny(fullText, ['amazon', 'flipkart', 'myntra', 'online'])) {
        return 'Online Shopping';
      }
      return 'Shopping';
    }

    if (_containsAny(fullText, ['paid', 'payment', 'bill'])) {
      if (_containsAny(fullText, ['electricity', 'power', 'light'])) return 'Electricity';
      if (_containsAny(fullText, ['water'])) return 'Water';
      if (_containsAny(fullText, ['gas', 'cylinder'])) return 'Gas';
      if (_containsAny(fullText, ['internet', 'wifi', 'broadband'])) return 'Internet';
      if (_containsAny(fullText, ['mobile', 'phone', 'recharge'])) return 'Mobile Recharge';
      if (_containsAny(fullText, ['credit card', 'cc'])) return 'Credit Card';
      return 'Household';
    }

    if (_containsAny(fullText, ['ate', 'eat', 'food', 'meal'])) {
      return 'Restaurants';
    }

    if (_containsAny(fullText, ['travel', 'trip', 'went', 'visited'])) {
      if (_containsAny(fullText, ['work', 'office', 'client', 'meeting'])) {
        return 'Work Travel';
      }
      return 'Travel';
    }

    if (_containsAny(fullText, ['ride', 'drove', 'commute'])) {
      return 'Cab';
    }

    // Default category
    return 'Miscellaneous';
  }

  bool _containsAny(String text, List<String> keywords) {
    for (final keyword in keywords) {
      if (text.contains(keyword)) return true;
    }
    return false;
  }

  /// Calculate Levenshtein distance between two strings
  int _levenshteinDistance(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    List<int> v0 = List<int>.generate(s2.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(s2.length + 1, 0);

    for (int i = 0; i < s1.length; i++) {
      v1[0] = i + 1;

      for (int j = 0; j < s2.length; j++) {
        final cost = s1[i] == s2[j] ? 0 : 1;
        v1[j + 1] = min(min(v1[j] + 1, v0[j + 1] + 1), v0[j] + cost);
      }

      final temp = v0;
      v0 = v1;
      v1 = temp;
    }

    return v0[s2.length];
  }

  /// Calculate similarity percentage between two strings (0.0 to 1.0)
  double _similarity(String s1, String s2) {
    final s1Lower = s1.toLowerCase();
    final s2Lower = s2.toLowerCase();

    if (s1Lower == s2Lower) return 1.0;

    final maxLen = s1.length > s2.length ? s1.length : s2.length;
    if (maxLen == 0) return 1.0;

    final distance = _levenshteinDistance(s1Lower, s2Lower);
    return 1.0 - (distance / maxLen);
  }

  /// Find best matching label from recent labels
  Future<String?> _findBestMatchingLabel(String inputLabel) async {
    final settingsProvider = context.read<SettingsProvider>();
    if (!settingsProvider.smartLabelMatching) return null;

    final dbService = DatabaseService();
    final recentLabels = await dbService.getRecentLabels(limit: 500);

    if (recentLabels.isEmpty) return null;

    String? bestMatch;
    double bestSimilarity = 0.0;
    const double threshold = 0.75; // 75% similarity threshold

    for (final label in recentLabels) {
      final similarity = _similarity(inputLabel, label);
      if (similarity > bestSimilarity && similarity >= threshold) {
        bestSimilarity = similarity;
        bestMatch = label;
      }
    }

    // Only return if it's not an exact match (exact matches are already handled)
    if (bestMatch != null && bestMatch.toLowerCase() != inputLabel.toLowerCase()) {
      debugPrint('Smart match: "$inputLabel" -> "$bestMatch" (${(bestSimilarity * 100).toInt()}%)');
      return bestMatch;
    }

    return null;
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Listening indicator with speech text
        if (_isListening)
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            constraints: const BoxConstraints(maxWidth: 300),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildWaveBar(0),
                    _buildWaveBar(1),
                    _buildWaveBar(2),
                    _buildWaveBar(3),
                    _buildWaveBar(4),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _lastWords.isEmpty ? 'Listening...' : _lastWords,
                  style: TextStyle(
                    fontSize: 16,
                    color: _lastWords.isEmpty ? Colors.grey[500] : Colors.black87,
                    fontStyle: _lastWords.isEmpty ? FontStyle.italic : FontStyle.normal,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (_lastWords.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Auto-stops when you pause',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ],
            ),
          ),

        // Animated FAB with pulse effect
        Stack(
          alignment: Alignment.center,
          children: [
            // Pulse animation rings
            if (_isListening) ...[
              AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _scaleAnimation.value,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.red.withOpacity(_opacityAnimation.value),
                      ),
                    ),
                  );
                },
              ),
              AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _scaleAnimation.value * 0.85,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.red.withOpacity(_opacityAnimation.value * 0.7),
                      ),
                    ),
                  );
                },
              ),
            ],
            // Main FAB - circular
            SizedBox(
              width: 72,
              height: 72,
              child: FloatingActionButton(
                onPressed: _isListening ? _stopListening : _startListening,
                backgroundColor: _isListening
                    ? Colors.red
                    : Theme.of(context).colorScheme.primary,
                shape: const CircleBorder(),
                child: Icon(
                  _isListening ? Icons.stop : Icons.mic,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWaveBar(int index) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        final offset = index * 0.2;
        final value = (_animationController.value + offset) % 1.0;
        final height = 8.0 + (sin(value * 3.14159 * 2) + 1) * 12;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: 4,
          height: height,
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.8),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      },
    );
  }
}
