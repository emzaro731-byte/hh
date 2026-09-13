import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/auth_screen.dart';
import 'screens/chat_screen.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabasePublishableKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  if (supabaseUrl.isEmpty || supabasePublishableKey.isEmpty) {
    runApp(const ConfigErrorApp());
    return;
  }
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
  );
  runApp(VeyloraApp(prefs: prefs));
}

class VeyloraApp extends StatelessWidget {
  final SharedPreferences prefs;
  const VeyloraApp({super.key, required this.prefs});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'VEYLORA AI',
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

class AuthGate extends StatefulWidget {
  final SharedPreferences prefs;
  const AuthGate({super.key, required this.prefs});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Stream<AuthState> _authStream;
  @override
  void initState() {
    super.initState();
    _authStream = Supabase.instance.client.auth.onAuthStateChange;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: _authStream,
      builder: (context, snapshot) {
        final event = snapshot.data?.event;
        if (event == AuthChangeEvent.passwordRecovery) return const UpdatePasswordScreen();
        final session = Supabase.instance.client.auth.currentSession;
        if (session == null) return const AuthScreen();
        return ChatScreen(prefs: widget.prefs);
      },
    );
  }
}

class ConfigErrorApp extends StatelessWidget {
  const ConfigErrorApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: const Color(0xFF070A10),
      body: const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('VEYLORA AI is missing Supabase configuration. Build with SUPABASE_URL and SUPABASE_ANON_KEY.', textAlign: TextAlign.center, style: TextStyle(fontSize: 17)))),
    ),
  );
}
