import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppTheme {
  navyBlue(
    displayName: 'Navy Blue',
    primaryColor: Color(0xFF1B3C53),
    primaryDarkColor: Color(0xFF234C6A),
    secondaryColor: Color(0xFF456882),
    accentColor: Color(0xFF4384B5),
  ),
  purplePlum(
    displayName: 'Purple Plum',
    primaryColor: Color(0xFF574964),
    primaryDarkColor: Color(0xFF9F8383),
    secondaryColor: Color(0xFFC8AAAA),
    accentColor: Color(0xFFFFDAB3),
  ),
  forestGold(
    displayName: 'Forest Gold',
    primaryColor: Color(0xFF2D3C59),
    primaryDarkColor: Color(0xFF94A378),
    secondaryColor: Color(0xFFE5BA41),
    accentColor: Color(0xFFFFDAB3),
  ),
  tealCoral(
    displayName: 'Teal Coral',
    primaryColor: Color(0xFF3F9AAE),
    primaryDarkColor: Color(0xFF79C9C5),
    secondaryColor: Color(0xFFFFE2AF),
    accentColor: Color(0xFFF96E5B),
  ),
  coastalEmber(
    displayName: 'Coastal Ember',
    primaryColor: Color(0xFF025259),
    primaryDarkColor: Color(0xFF007172),
    secondaryColor: Color(0xFFF29325),
    accentColor: Color(0xFFD94F04),
  );

  final String displayName;
  final Color primaryColor;
  final Color primaryDarkColor;
  final Color secondaryColor;
  final Color accentColor;

  const AppTheme({
    required this.displayName,
    required this.primaryColor,
    required this.primaryDarkColor,
    required this.secondaryColor,
    required this.accentColor,
  });

  ThemeData toThemeData() {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        primary: primaryColor,
        secondary: secondaryColor,
        tertiary: accentColor,
      ),
      useMaterial3: true,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      cardTheme: CardTheme(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 4,
        backgroundColor: primaryColor,
      ),
    );
  }
}

class SettingsService {
  static const String _currencyKey = 'currency';
  static const String _isFirstLaunchKey = 'is_first_launch';
  static const String _themeKey = 'app_theme';
  static const String _speechLocaleKey = 'speech_locale';
  static const String _smartLabelMatchingKey = 'smart_label_matching';

  final Map<String, String> currencySymbols = {
    'USD': '\$',
    'EUR': '\u20AC',
    'GBP': '\u00A3',
    'INR': '\u20B9',
    'JPY': '\u00A5',
    'CAD': 'C\$',
    'AUD': 'A\$',
  };

  final Map<String, String> currencyNames = {
    'USD': 'US Dollar',
    'EUR': 'Euro',
    'GBP': 'British Pound',
    'INR': 'Indian Rupee',
    'JPY': 'Japanese Yen',
    'CAD': 'Canadian Dollar',
    'AUD': 'Australian Dollar',
  };

  Future<String> getCurrency() async {
    final prefs = await SharedPreferences.getInstance();
    final isFirstLaunch = prefs.getBool(_isFirstLaunchKey) ?? true;

    if (isFirstLaunch) {
      final detectedCurrency = _detectCurrencyFromTimezone();
      await prefs.setString(_currencyKey, detectedCurrency);
      await prefs.setBool(_isFirstLaunchKey, false);
      return detectedCurrency;
    }

    return prefs.getString(_currencyKey) ?? 'USD';
  }

  Future<void> setCurrency(String currency) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currencyKey, currency);
  }

  String _detectCurrencyFromTimezone() {
    final timezone = DateTime.now().timeZoneName;
    final offset = DateTime.now().timeZoneOffset;

    // Detect based on timezone offset and name
    if (timezone.contains('IST') || offset.inHours == 5 && offset.inMinutes == 30) {
      return 'INR';
    } else if (timezone.contains('GMT') || timezone.contains('BST')) {
      return 'GBP';
    } else if (timezone.contains('CET') || timezone.contains('CEST')) {
      return 'EUR';
    } else if (timezone.contains('JST') || offset.inHours == 9) {
      return 'JPY';
    } else if (offset.inHours >= -5 && offset.inHours <= -4) {
      // Eastern US timezone
      return 'USD';
    } else if (offset.inHours >= -8 && offset.inHours <= -7) {
      // Pacific US timezone
      return 'USD';
    } else if (offset.inHours == 10 || offset.inHours == 11) {
      // Australia Eastern
      return 'AUD';
    }

    return 'USD';
  }

  String getSymbol(String currency) {
    return currencySymbols[currency] ?? '\$';
  }

  List<String> get supportedCurrencies => currencySymbols.keys.toList();

  Future<AppTheme> getTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeName = prefs.getString(_themeKey);
    if (themeName != null) {
      return AppTheme.values.firstWhere(
        (t) => t.name == themeName,
        orElse: () => AppTheme.navyBlue,
      );
    }
    return AppTheme.navyBlue;
  }

  Future<void> setTheme(AppTheme theme) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, theme.name);
  }

  // English speech locales with regional accents
  final Map<String, String> speechLocales = {
    'en_IN': 'English (India)',
    'en_US': 'English (US)',
    'en_GB': 'English (UK)',
    'en_AU': 'English (Australia)',
    'en_CA': 'English (Canada)',
    'en_NZ': 'English (New Zealand)',
    'en_ZA': 'English (South Africa)',
    'en_IE': 'English (Ireland)',
    'en_SG': 'English (Singapore)',
    'en_PH': 'English (Philippines)',
    'en_KE': 'English (Kenya)',
    'en_NG': 'English (Nigeria)',
  };

  Future<String?> getSpeechLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLocale = prefs.getString(_speechLocaleKey);

    // If no saved locale, detect from timezone and save it
    if (savedLocale == null) {
      final detectedLocale = _detectSpeechLocaleFromTimezone();
      await prefs.setString(_speechLocaleKey, detectedLocale);
      return detectedLocale;
    }

    return savedLocale;
  }

  String _detectSpeechLocaleFromTimezone() {
    final timezone = DateTime.now().timeZoneName;
    final offset = DateTime.now().timeZoneOffset;

    // Detect English variant based on timezone
    if (timezone.contains('IST') || (offset.inHours == 5 && offset.inMinutes == 30)) {
      return 'en_IN'; // India
    } else if (timezone.contains('GMT') || timezone.contains('BST')) {
      return 'en_GB'; // UK
    } else if (offset.inHours == 10 || offset.inHours == 11) {
      return 'en_AU'; // Australia
    } else if (offset.inHours == 12 || offset.inHours == 13) {
      return 'en_NZ'; // New Zealand
    } else if (offset.inHours == 8 && timezone.contains('SGT')) {
      return 'en_SG'; // Singapore
    } else if (offset.inHours == 8 && timezone.contains('PHT')) {
      return 'en_PH'; // Philippines
    } else if (offset.inHours == 2) {
      return 'en_ZA'; // South Africa
    } else if (offset.inHours == 3 && timezone.contains('EAT')) {
      return 'en_KE'; // Kenya
    } else if (offset.inHours == 1 && timezone.contains('WAT')) {
      return 'en_NG'; // Nigeria
    } else if (timezone.contains('IST') && offset.inHours == 0) {
      return 'en_IE'; // Ireland
    } else if (offset.inHours >= -5 && offset.inHours <= -4) {
      return 'en_US'; // Eastern US / Canada
    } else if (offset.inHours >= -8 && offset.inHours <= -7) {
      return 'en_US'; // Pacific US / Canada
    }

    return 'en_US'; // Default to US English
  }

  Future<void> setSpeechLocale(String? localeId) async {
    final prefs = await SharedPreferences.getInstance();
    if (localeId == null) {
      await prefs.remove(_speechLocaleKey);
    } else {
      await prefs.setString(_speechLocaleKey, localeId);
    }
  }

  List<String> get supportedSpeechLocales => speechLocales.keys.toList();

  String getSpeechLocaleDisplayName(String localeId) {
    return speechLocales[localeId] ?? localeId;
  }

  Future<bool> getSmartLabelMatching() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_smartLabelMatchingKey) ?? true; // Enabled by default
  }

  Future<void> setSmartLabelMatching(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_smartLabelMatchingKey, enabled);
  }
}
