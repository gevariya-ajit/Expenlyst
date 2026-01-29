import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/expense_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/sync_provider.dart';
import 'providers/subscription_provider.dart';
import 'screens/home_screen.dart';
import 'screens/lock_screen.dart';
import 'services/local_auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock app to portrait mode only
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ExpenseProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()..loadSettings()),
        ChangeNotifierProvider(create: (_) => SyncProvider()..init()),
        ChangeNotifierProvider(create: (_) => SubscriptionProvider()),
      ],
      child: const _AppWithAutoSync(),
    );
  }
}

/// Widget that sets up auto sync connection between providers
class _AppWithAutoSync extends StatefulWidget {
  const _AppWithAutoSync();

  @override
  State<_AppWithAutoSync> createState() => _AppWithAutoSyncState();
}

class _AppWithAutoSyncState extends State<_AppWithAutoSync> {
  @override
  void initState() {
    super.initState();
    // Connect expense changes to auto sync after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final expenseProvider = context.read<ExpenseProvider>();
      final syncProvider = context.read<SyncProvider>();

      expenseProvider.onDataChanged = () {
        syncProvider.triggerAutoSync();
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settingsProvider, child) {
        return MaterialApp(
          title: 'Expenlyst',
          debugShowCheckedModeBanner: false,
          theme: settingsProvider.themeData,
          home: const AuthWrapper(),
        );
      },
    );
  }
}

/// Wrapper widget that handles app lock authentication
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> with WidgetsBindingObserver {
  bool _isAuthenticated = false;
  bool _isCheckingAuth = true;
  bool _wasInBackground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAuthRequired();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _wasInBackground = true;
    } else if (state == AppLifecycleState.resumed && _wasInBackground) {
      _wasInBackground = false;
      _checkAuthOnResume();
    }
  }

  Future<void> _checkAuthRequired() async {
    final isLockEnabled = await LocalAuthService.isAppLockEnabled();

    if (isLockEnabled) {
      setState(() {
        _isCheckingAuth = false;
        _isAuthenticated = false;
      });
    } else {
      setState(() {
        _isCheckingAuth = false;
        _isAuthenticated = true;
      });
    }
  }

  Future<void> _checkAuthOnResume() async {
    final isLockEnabled = await LocalAuthService.isAppLockEnabled();

    if (isLockEnabled && _isAuthenticated) {
      setState(() {
        _isAuthenticated = false;
      });
    }
  }

  void _onAuthenticated() {
    setState(() {
      _isAuthenticated = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingAuth) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!_isAuthenticated) {
      return LockScreen(onAuthenticated: _onAuthenticated);
    }

    return const HomeScreen();
  }
}
