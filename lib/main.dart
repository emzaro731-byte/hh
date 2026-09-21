import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/auth_screen.dart';
import 'screens/trading_dashboard_screen.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
const supabasePublishableKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (supabaseUrl.isEmpty || supabasePublishableKey.isEmpty) {
    throw Exception('Missing SUPABASE_URL or SUPABASE_ANON_KEY.');
  }
  final prefs = await SharedPreferences.getInstance();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabasePublishableKey);
  runApp(VeylolaApp(prefs: prefs));
}

class VeylolaApp extends StatelessWidget {
  final SharedPreferences prefs;
  const VeylolaApp({super.key, required this.prefs});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'VEYLOLA',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF070A12),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7C5CFF), brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: AuthGate(prefs: prefs),
    );
  }
}

class AuthGate extends StatelessWidget {
  final SharedPreferences prefs;
  const AuthGate({super.key, required this.prefs});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.data?.event == AuthChangeEvent.passwordRecovery) {
          return const UpdatePasswordScreen();
        }
        final session = Supabase.instance.client.auth.currentSession;
        return session == null ? const AuthScreen() : const TradingDashboardScreen();
      },
    );
  }
}
