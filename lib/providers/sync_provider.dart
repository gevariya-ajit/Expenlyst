import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../services/google_auth_service.dart';
import '../services/sheets_service.dart';
import '../services/sync_service.dart';
import '../services/database_service.dart';

enum SyncState {
  idle,
  syncing,
  success,
  error,
}

/// User profile data persisted locally
class UserProfile {
  final String? displayName;
  final String? email;
  final String? photoUrl;

  UserProfile({
    this.displayName,
    this.email,
    this.photoUrl,
  });

  bool get hasData => displayName != null || email != null;

  String get initials {
    if (displayName != null && displayName!.isNotEmpty) {
      final parts = displayName!.split(' ');
      if (parts.length >= 2) {
        return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
      }
      return displayName![0].toUpperCase();
    }
    if (email != null && email!.isNotEmpty) {
      return email![0].toUpperCase();
    }
    return 'U';
  }
}

class SyncProvider with ChangeNotifier {
  final GoogleAuthService _authService = GoogleAuthService();
  final SheetsService _sheetsService = SheetsService();
  final SyncService _syncService = SyncService();
  final DatabaseService _databaseService = DatabaseService();

  // Storage keys
  static const String _lastSyncTimeKey = 'last_sync_time';
  static const String _selectedSheetIdKey = 'selected_sheet_id';
  static const String _selectedSheetNameKey = 'selected_sheet_name';
  static const String _deviceIdKey = 'device_id';
  static const String _autoSyncEnabledKey = 'auto_sync_enabled';
  static const String _userDisplayNameKey = 'user_display_name';
  static const String _userEmailKey = 'user_email';
  static const String _userPhotoUrlKey = 'user_photo_url';

  bool _isSignedIn = false;
  GoogleSignInAccount? _currentUser;
  UserProfile _userProfile = UserProfile();
  SyncState _syncState = SyncState.idle;
  String? _syncError;
  DateTime? _lastSyncTime;
  String? _selectedSheetId;
  String? _selectedSheetName;
  String? _deviceId;
  bool _autoSyncEnabled = true;
  List<SheetInfo> _availableSheets = [];

  bool get isSignedIn => _isSignedIn;
  GoogleSignInAccount? get currentUser => _currentUser;
  UserProfile get userProfile => _userProfile;
  SyncState get syncState => _syncState;
  String? get syncError => _syncError;
  DateTime? get lastSyncTime => _lastSyncTime;
  String? get selectedSheetId => _selectedSheetId;
  String? get selectedSheetName => _selectedSheetName;
  String get deviceId => _deviceId ?? '';
  bool get autoSyncEnabled => _autoSyncEnabled;
  List<SheetInfo> get availableSheets => _availableSheets;
  bool get hasSelectedSheet => _selectedSheetId != null && _selectedSheetId!.isNotEmpty;

  // Convenience getters for user profile
  String? get userName => _userProfile.displayName ?? _currentUser?.displayName;
  String? get userEmail => _userProfile.email ?? _currentUser?.email;
  String? get userPhotoUrl => _userProfile.photoUrl ?? _currentUser?.photoUrl;
  String get userInitials => _userProfile.initials;

  /// Initialize provider - load settings and try silent sign-in
  Future<void> init() async {
    await _loadSettings();
    final silentSuccess = await _authService.init();
    if (silentSuccess) {
      _isSignedIn = true;
      _currentUser = _authService.currentUser;
      // Update profile if we have fresh data from Google
      if (_currentUser != null) {
        await _saveUserProfile(_currentUser!);
      }
    }
    notifyListeners();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    final lastSyncTimeStr = prefs.getString(_lastSyncTimeKey);
    if (lastSyncTimeStr != null) {
      _lastSyncTime = DateTime.tryParse(lastSyncTimeStr);
    }

    _selectedSheetId = prefs.getString(_selectedSheetIdKey);
    _selectedSheetName = prefs.getString(_selectedSheetNameKey);
    _autoSyncEnabled = prefs.getBool(_autoSyncEnabledKey) ?? true;

    // Load user profile
    _userProfile = UserProfile(
      displayName: prefs.getString(_userDisplayNameKey),
      email: prefs.getString(_userEmailKey),
      photoUrl: prefs.getString(_userPhotoUrlKey),
    );

    // If we have stored profile data, consider user as signed in (until verified)
    if (_userProfile.hasData) {
      _isSignedIn = true;
    }

    // Get or generate device ID
    _deviceId = prefs.getString(_deviceIdKey);
    if (_deviceId == null) {
      _deviceId = const Uuid().v4();
      await prefs.setString(_deviceIdKey, _deviceId!);
    }
  }

  Future<void> _saveUserProfile(GoogleSignInAccount user) async {
    final prefs = await SharedPreferences.getInstance();

    if (user.displayName != null) {
      await prefs.setString(_userDisplayNameKey, user.displayName!);
    }
    if (user.email.isNotEmpty) {
      await prefs.setString(_userEmailKey, user.email);
    }
    if (user.photoUrl != null) {
      await prefs.setString(_userPhotoUrlKey, user.photoUrl!);
    }

    _userProfile = UserProfile(
      displayName: user.displayName,
      email: user.email,
      photoUrl: user.photoUrl,
    );
  }

  Future<void> _clearUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userDisplayNameKey);
    await prefs.remove(_userEmailKey);
    await prefs.remove(_userPhotoUrlKey);
    _userProfile = UserProfile();
  }

  Future<void> _saveLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    if (_lastSyncTime != null) {
      await prefs.setString(_lastSyncTimeKey, _lastSyncTime!.toIso8601String());
    }
  }

  Future<void> _saveSelectedSheet() async {
    final prefs = await SharedPreferences.getInstance();
    if (_selectedSheetId != null) {
      await prefs.setString(_selectedSheetIdKey, _selectedSheetId!);
    } else {
      await prefs.remove(_selectedSheetIdKey);
    }
    if (_selectedSheetName != null) {
      await prefs.setString(_selectedSheetNameKey, _selectedSheetName!);
    } else {
      await prefs.remove(_selectedSheetNameKey);
    }
  }

  /// Sign in with Google
  Future<bool> signIn() async {
    final user = await _authService.signIn();
    if (user != null) {
      _isSignedIn = true;
      _currentUser = user;
      await _saveUserProfile(user);
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Sign out and clear local data
  Future<void> signOut() async {
    await _authService.signOut();
    await _databaseService.clearAllExpenses();
    await _clearUserProfile();

    _isSignedIn = false;
    _currentUser = null;
    _selectedSheetId = null;
    _selectedSheetName = null;
    _lastSyncTime = null;
    _availableSheets = [];
    _syncState = SyncState.idle;
    _syncError = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastSyncTimeKey);
    await prefs.remove(_selectedSheetIdKey);
    await prefs.remove(_selectedSheetNameKey);

    notifyListeners();
  }

  /// Set auto sync enabled
  Future<void> setAutoSyncEnabled(bool enabled) async {
    _autoSyncEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoSyncEnabledKey, enabled);
    notifyListeners();
  }

  /// Load available sheets from Google Drive
  Future<void> loadAvailableSheets() async {
    if (!_isSignedIn) return;

    final client = await _authService.getAuthenticatedClient();
    if (client == null) return;

    try {
      _availableSheets = await _sheetsService.listExpenlystSheets(client);
      notifyListeners();
    } finally {
      client.close();
    }
  }

  /// Create a new Expenlyst spreadsheet
  Future<String?> createNewSheet({String name = 'Expenlyst Expenses'}) async {
    if (!_isSignedIn) return null;

    final client = await _authService.getAuthenticatedClient();
    if (client == null) return null;

    try {
      final sheetId = await _sheetsService.createSpreadsheet(client, name: name);
      if (sheetId != null) {
        _selectedSheetId = sheetId;
        _selectedSheetName = name;
        await _saveSelectedSheet();
        await loadAvailableSheets();
        notifyListeners();
      }
      return sheetId;
    } finally {
      client.close();
    }
  }

  /// Select an existing sheet and download subscriptions
  Future<void> selectSheet(SheetInfo sheet) async {
    _selectedSheetId = sheet.id;
    _selectedSheetName = sheet.name;
    await _saveSelectedSheet();
    notifyListeners();

    // Download subscriptions from the selected sheet
    await _downloadSubscriptionsFromSheet();
  }

  /// Download subscriptions from current sheet (called when sheet is selected)
  /// Clears all local subscriptions first, then downloads from cloud
  Future<void> _downloadSubscriptionsFromSheet() async {
    if (!_isSignedIn || _selectedSheetId == null) return;

    final client = await _authService.getAuthenticatedClient();
    if (client == null) return;

    try {
      // Clear all local subscriptions first
      debugPrint('Clearing local subscriptions before download...');
      await _databaseService.clearAllSubscriptions();

      // Download subscriptions from the selected sheet
      debugPrint('Downloading subscriptions from selected sheet...');
      final result = await _syncService.downloadSubscriptions(
        client,
        _selectedSheetId!,
      );
      debugPrint('Downloaded ${result.downloaded} subscriptions');
    } catch (e) {
      debugPrint('Error downloading subscriptions: $e');
    } finally {
      client.close();
    }
  }

  /// Perform full sync
  Future<SyncStatus> syncNow() async {
    if (!_isSignedIn || _selectedSheetId == null) {
      return SyncStatus(
        result: SyncResult.authError,
        errorMessage: 'Not signed in or no sheet selected',
      );
    }

    _syncState = SyncState.syncing;
    _syncError = null;
    notifyListeners();

    final client = await _authService.getAuthenticatedClient();
    if (client == null) {
      _syncState = SyncState.error;
      _syncError = 'Failed to get authenticated client';
      notifyListeners();
      return SyncStatus(
        result: SyncResult.authError,
        errorMessage: 'Failed to get authenticated client',
      );
    }

    try {
      // Sync expenses
      final expenseResult = await _syncService.syncAll(
        client,
        _selectedSheetId!,
        _lastSyncTime,
        _deviceId!,
      );

      // Sync subscriptions
      final subscriptionResult = await _syncService.syncAllSubscriptions(
        client,
        _selectedSheetId!,
      );

      // Combine results
      final isSuccess = expenseResult.isSuccess && subscriptionResult.isSuccess;
      if (isSuccess) {
        _lastSyncTime = DateTime.now();
        await _saveLastSyncTime();
        _syncState = SyncState.success;
      } else {
        _syncState = SyncState.error;
        _syncError = expenseResult.errorMessage ?? subscriptionResult.errorMessage;
      }

      notifyListeners();
      return SyncStatus(
        result: isSuccess ? SyncResult.success : SyncResult.unknownError,
        uploaded: expenseResult.uploaded + subscriptionResult.uploaded,
        downloaded: expenseResult.downloaded + subscriptionResult.downloaded,
        errorMessage: _syncError,
      );
    } finally {
      client.close();
    }
  }

  /// Initial upload to a new sheet
  Future<SyncStatus> initialUpload() async {
    if (!_isSignedIn || _selectedSheetId == null) {
      return SyncStatus(
        result: SyncResult.authError,
        errorMessage: 'Not signed in or no sheet selected',
      );
    }

    _syncState = SyncState.syncing;
    _syncError = null;
    notifyListeners();

    final client = await _authService.getAuthenticatedClient();
    if (client == null) {
      _syncState = SyncState.error;
      _syncError = 'Failed to get authenticated client';
      notifyListeners();
      return SyncStatus(
        result: SyncResult.authError,
        errorMessage: 'Failed to get authenticated client',
      );
    }

    try {
      // Upload expenses
      final expenseResult = await _syncService.initialUpload(
        client,
        _selectedSheetId!,
        _deviceId!,
      );

      // Upload subscriptions
      final subscriptionResult = await _syncService.uploadSubscriptions(
        client,
        _selectedSheetId!,
      );

      final isSuccess = expenseResult.isSuccess && subscriptionResult.isSuccess;
      if (isSuccess) {
        _lastSyncTime = DateTime.now();
        await _saveLastSyncTime();
        _syncState = SyncState.success;
      } else {
        _syncState = SyncState.error;
        _syncError = expenseResult.errorMessage ?? subscriptionResult.errorMessage;
      }

      notifyListeners();
      return SyncStatus(
        result: isSuccess ? SyncResult.success : SyncResult.unknownError,
        uploaded: expenseResult.uploaded + subscriptionResult.uploaded,
        errorMessage: _syncError,
      );
    } finally {
      client.close();
    }
  }

  /// Restore from cloud (replaces local data)
  Future<SyncStatus> restoreFromCloud() async {
    if (!_isSignedIn || _selectedSheetId == null) {
      return SyncStatus(
        result: SyncResult.authError,
        errorMessage: 'Not signed in or no sheet selected',
      );
    }

    _syncState = SyncState.syncing;
    _syncError = null;
    notifyListeners();

    final client = await _authService.getAuthenticatedClient();
    if (client == null) {
      _syncState = SyncState.error;
      _syncError = 'Failed to get authenticated client';
      notifyListeners();
      return SyncStatus(
        result: SyncResult.authError,
        errorMessage: 'Failed to get authenticated client',
      );
    }

    try {
      // Restore expenses
      final expenseResult = await _syncService.restoreFromCloud(
        client,
        _selectedSheetId!,
      );

      // Download subscriptions
      final subscriptionResult = await _syncService.downloadSubscriptions(
        client,
        _selectedSheetId!,
      );

      final isSuccess = expenseResult.isSuccess && subscriptionResult.isSuccess;
      if (isSuccess) {
        _lastSyncTime = DateTime.now();
        await _saveLastSyncTime();
        _syncState = SyncState.success;
      } else {
        _syncState = SyncState.error;
        _syncError = expenseResult.errorMessage ?? subscriptionResult.errorMessage;
      }

      notifyListeners();
      return SyncStatus(
        result: isSuccess ? SyncResult.success : SyncResult.unknownError,
        downloaded: expenseResult.downloaded + subscriptionResult.downloaded,
        errorMessage: _syncError,
      );
    } finally {
      client.close();
    }
  }

  /// Trigger sync if auto-sync is enabled
  Future<void> triggerAutoSync() async {
    if (_autoSyncEnabled && _isSignedIn && hasSelectedSheet) {
      await syncNow();
    }
  }

  /// Get formatted last sync time
  String getLastSyncTimeFormatted() {
    if (_lastSyncTime == null) return 'Never';

    final now = DateTime.now();
    final diff = now.difference(_lastSyncTime!);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes} min ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours} hours ago';
    } else {
      return '${diff.inDays} days ago';
    }
  }
}
