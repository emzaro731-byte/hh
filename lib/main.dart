import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/auth_screen.dart';
import 'screens/studio_screen.dart';

const supabaseUrl = 'https://vihbsfrwnslnmheowkhy.supabase.co';
const supabasePublishableKey = 'sb_publishable_j8gV4-PeFte1RMgl759uQQ_KrM_3vzK';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabasePublishableKey);
  runApp(VeyloraApp(prefs: prefs));
}

class VeyloraApp extends StatelessWidget {
  final SharedPreferences prefs;
  const VeyloraApp({super.key, required this.prefs});
  @override
  Widget build(BuildContext context) => MaterialApp(
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

class AuthGate extends StatefulWidget {
  final SharedPreferences prefs;
  const AuthGate({super.key, required this.prefs});
  @override State<AuthGate> createState() => _AuthGateState();
}
class _AuthGateState extends State<AuthGate> {
  late final Stream<AuthState> _authStream;
  @override void initState() { super.initState(); _authStream = Supabase.instance.client.auth.onAuthStateChange; }
  @override Widget build(BuildContext context) => StreamBuilder<AuthState>(
    stream: _authStream,
    builder: (_, snapshot) {
      if (snapshot.data?.event == AuthChangeEvent.passwordRecovery) return const UpdatePasswordScreen();
      return Supabase.instance.client.auth.currentSession == null
          ? const AuthScreen()
          : StudioScreen(prefs: widget.prefs);
    },
  );
}
