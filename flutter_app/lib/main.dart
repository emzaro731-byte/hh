import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_page.dart';
import 'home_page.dart';
import 'services/push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_ANON_KEY');

  if (url.isEmpty || key.isEmpty) {
    runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('Configure SUPABASE_URL and SUPABASE_ANON_KEY.')))));
    return;
  }

  await Supabase.initialize(url: url, anonKey: key);

  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Firebase is optional during local development without google-services.json.
  }

  runApp(const GGApp());

  if (Firebase.apps.isNotEmpty) {
    Supabase.instance.client.auth.onAuthStateChange.listen((_) async {
      if (Supabase.instance.client.auth.currentUser != null) {
        try {
          await PushService(Supabase.instance.client).initialize();
        } catch (_) {}
      }
    });
  }
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
