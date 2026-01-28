import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/settings_service.dart';

class SettingsProvider with ChangeNotifier {
  final SettingsService _settingsService = SettingsService();

  String _currency = 'USD';
  AppTheme _theme = AppTheme.navyBlue;
  String? _speechLocale;
  bool _smartLabelMatching = true;
  bool _isLoading = true;

  String get currency => _currency;
  AppTheme get theme => _theme;
  ThemeData get themeData => _theme.toThemeData();
  String? get speechLocale => _speechLocale;
  bool get smartLabelMatching => _smartLabelMatching;
  bool get isLoading => _isLoading;

  String get currencySymbol => _settingsService.getSymbol(_currency);

  Map<String, String> get currencySymbols => _settingsService.currencySymbols;
  Map<String, String> get currencyNames => _settingsService.currencyNames;
  List<String> get supportedCurrencies => _settingsService.supportedCurrencies;
  List<AppTheme> get availableThemes => AppTheme.values;

  Map<String, String> get speechLocales => _settingsService.speechLocales;
  List<String> get supportedSpeechLocales => _settingsService.supportedSpeechLocales;
  String getSpeechLocaleDisplayName(String localeId) => _settingsService.getSpeechLocaleDisplayName(localeId);

  Future<void> loadSettings() async {
    _isLoading = true;
    notifyListeners();

    try {
      _currency = await _settingsService.getCurrency();
      _theme = await _settingsService.getTheme();
      _speechLocale = await _settingsService.getSpeechLocale();
      _smartLabelMatching = await _settingsService.getSmartLabelMatching();
    } catch (e) {
      debugPrint('Error loading settings: $e');
      _currency = 'USD';
      _theme = AppTheme.navyBlue;
      _speechLocale = null;
      _smartLabelMatching = true;
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> setCurrency(String currency) async {
    try {
      await _settingsService.setCurrency(currency);
      _currency = currency;
      notifyListeners();
    } catch (e) {
      debugPrint('Error setting currency: $e');
    }
  }

  Future<void> setTheme(AppTheme theme) async {
    try {
      await _settingsService.setTheme(theme);
      _theme = theme;
      notifyListeners();
    } catch (e) {
      debugPrint('Error setting theme: $e');
    }
  }

  Future<void> setSpeechLocale(String? localeId) async {
    try {
      await _settingsService.setSpeechLocale(localeId);
      _speechLocale = localeId;
      notifyListeners();
    } catch (e) {
      debugPrint('Error setting speech locale: $e');
    }
  }

  Future<void> setSmartLabelMatching(bool enabled) async {
    try {
      await _settingsService.setSmartLabelMatching(enabled);
      _smartLabelMatching = enabled;
      notifyListeners();
    } catch (e) {
      debugPrint('Error setting smart label matching: $e');
    }
  }

  String formatAmount(double amount) {
    final symbol = currencySymbol;
    if (_currency == 'JPY') {
      return '$symbol${amount.toInt()}';
    }
    return '$symbol${amount.toStringAsFixed(2)}';
  }
}
