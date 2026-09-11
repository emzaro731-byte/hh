import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_page.dart';
import 'home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_ANON_KEY');
  if (url.isEmpty || key.isEmpty) {
    runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('Configure SUPABASE_URL and SUPABASE_ANON_KEY with --dart-define.')))));
    return;
  }
  await Supabase.initialize(url: url, anonKey: key);
  runApp(const GGApp());
}

class GGApp extends StatelessWidget {
  const GGApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'GG Messenger',
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xff2563eb)),
    home: StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (_, __) => Supabase.instance.client.auth.currentSession == null ? const AuthPage() : const HomePage(),
    ),
  );
}
