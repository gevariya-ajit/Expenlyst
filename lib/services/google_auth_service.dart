import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

class GoogleAuthService {
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'https://www.googleapis.com/auth/spreadsheets',
      'https://www.googleapis.com/auth/drive.file',
    ],
  );

  GoogleSignInAccount? _currentUser;

  GoogleSignInAccount? get currentUser => _currentUser;
  bool get isSignedIn => _currentUser != null;

  /// Initialize and try to sign in silently
  Future<bool> init() async {
    try {
      _currentUser = await _googleSignIn.signInSilently();
      return _currentUser != null;
    } catch (e) {
      debugPrint('Error during silent sign-in: $e');
      return false;
    }
  }

  /// Sign in with Google
  Future<GoogleSignInAccount?> signIn() async {
    try {
      _currentUser = await _googleSignIn.signIn();
      return _currentUser;
    } catch (e, stackTrace) {
      debugPrint('=== Google Sign-In Error ===');
      debugPrint('Error: $e');
      debugPrint('Stack trace: $stackTrace');
      debugPrint('============================');
      return null;
    }
  }

  /// Sign out from Google
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      _currentUser = null;
    } catch (e) {
      debugPrint('Error during sign-out: $e');
    }
  }

  /// Disconnect (revoke access)
  Future<void> disconnect() async {
    try {
      await _googleSignIn.disconnect();
      _currentUser = null;
    } catch (e) {
      debugPrint('Error during disconnect: $e');
    }
  }

  /// Get authenticated HTTP client for Google APIs
  Future<http.Client?> getAuthenticatedClient() async {
    if (_currentUser == null) {
      return null;
    }

    try {
      final auth = await _currentUser!.authentication;
      final accessToken = auth.accessToken;

      if (accessToken == null) {
        debugPrint('No access token available');
        return null;
      }

      final credentials = AccessCredentials(
        AccessToken(
          'Bearer',
          accessToken,
          DateTime.now().toUtc().add(const Duration(hours: 1)),
        ),
        null, // No refresh token with Google Sign-In
        [
          'https://www.googleapis.com/auth/spreadsheets',
          'https://www.googleapis.com/auth/drive.file',
        ],
      );

      return authenticatedClient(http.Client(), credentials);
    } catch (e) {
      debugPrint('Error getting authenticated client: $e');
      return null;
    }
  }

  /// Refresh authentication if needed
  Future<bool> refreshAuth() async {
    try {
      final account = await _googleSignIn.signInSilently(reAuthenticate: true);
      _currentUser = account;
      return account != null;
    } catch (e) {
      debugPrint('Error refreshing auth: $e');
      return false;
    }
  }
}
