import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'screens/auth_screen.dart';
import 'screens/verify_email_screen.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.instance.init();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.system;
  double _textScale = ProfileScreen.defaultTextScale;
  Color _accentColor = ProfileScreen.defaultAccent;

  // Created once. Calling authStateChanges() inside build() gives
  // StreamBuilder a brand-new stream on every rebuild (font size, theme and
  // accent changes all rebuild MyApp), which resets HomeScreen back to the
  // dashboard and reloads all tasks.
  late final Stream<User?> _authStream =
      FirebaseAuth.instance.authStateChanges();

  @override
  void initState() {
    super.initState();
    _loadAppearance();
  }

  Future<void> _loadAppearance() async {
    final prefs = await SharedPreferences.getInstance();

    final savedTheme = prefs.getString('themeMode');
    final mode = ThemeMode.values.firstWhere(
      (m) => m.name == savedTheme,
      orElse: () => ThemeMode.system,
    );

    final savedScale = prefs.getDouble('textScale');
    final savedAccent = prefs.getInt('accentColor');

    setState(() {
      _themeMode = mode;
      if (savedScale != null) {
        _textScale = savedScale
            .clamp(ProfileScreen.minTextScale, ProfileScreen.maxTextScale)
            .toDouble();
      }
      if (savedAccent != null) {
        _accentColor = Color(savedAccent);
      }
    });
  }

  Future<void> _handleThemeModeChanged(ThemeMode mode) async {
    setState(() {
      _themeMode = mode;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('themeMode', mode.name);
  }

  Future<void> _handleTextScaleChanged(double scale) async {
    setState(() {
      _textScale = scale;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('textScale', scale);
  }

  Future<void> _handleAccentColorChanged(Color color) async {
    setState(() {
      _accentColor = color;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('accentColor', color.toARGB32());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _accentColor),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _accentColor,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: _themeMode,
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        final systemScale = mediaQuery.textScaler.scale(1.0);
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: TextScaler.linear(systemScale * _textScale),
          ),
          child: child!,
        );
      },
      home: StreamBuilder<User?>(
        stream: _authStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          final user = snapshot.data;
          if (user == null) {
            return const AuthScreen();
          }

          // Read from currentUser so the reload() done on the verify screen
          // is picked up (the cached stream's user object can be stale).
          final isVerified =
              FirebaseAuth.instance.currentUser?.emailVerified ??
                  user.emailVerified;
          if (!isVerified) {
            return VerifyEmailScreen(onRefresh: () => setState(() {}));
          }

          return HomeScreen(
            themeMode: _themeMode,
            onThemeModeChanged: _handleThemeModeChanged,
            textScale: _textScale,
            onTextScaleChanged: _handleTextScaleChanged,
            accentColor: _accentColor,
            onAccentColorChanged: _handleAccentColorChanged,
          );
        },
      ),
    );
  }
}