import 'dart:math' show sin;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../models/expense.dart';
import '../providers/expense_provider.dart';

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

  Future<void> _processVoiceInput(String text) async {
    if (text.isEmpty) {
      _showSnackBar('No speech detected');
      return;
    }

    final parsed = _parseExpense(text);
    final label = parsed['label']!;

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

    final categorySource = existingCategory != null ? 'auto' : 'detected';
    _showSnackBar('Added: ${expense.label} - ${parsed['amount']} ($category - $categorySource)');
  }

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

    // Create a mutable list for processing
    List<String> labelWords = List.from(words);

    // Remove amount and currency words from label
    if (amountIndex != -1) {
      labelWords.removeAt(amountIndex);
      // Also remove currency words if present
      labelWords.removeWhere((w) =>
        w == 'dollars' || w == 'dollar' || w == 'rupees' || w == 'rupee' ||
        w == 'rs' || w == 'inr' || w == 'usd' || w == '\$' || w == 'rs.');
    }

    // Build label from remaining words
    String label = labelWords.where((w) => w.isNotEmpty).join(' ').trim();

    // If no label, use "Expense"
    if (label.isEmpty) {
      label = 'Expense';
    }

    // Capitalize first letter of each word
    label = _capitalizeWords(label);

    // Detect category based on the full text and label
    String category = _detectCategory(lowerText, label.toLowerCase());

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
