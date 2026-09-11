import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_page.dart';
import 'home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_ANON_KEY');

  if (url.isEmpty || key.isEmpty) {
    runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'GG Messenger could not start because the Supabase configuration is missing.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    ));
    return;
  }

  try {
    await Supabase.initialize(url: url, anonKey: key);
    runApp(const GGApp());
  } catch (e) {
    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'GG Messenger could not start.\n\n$e',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    ));
  }
}

class GGApp extends StatelessWidget {
  const GGApp({super.key});
  static const gold = Color(0xFFFFC83D);
  static const black = Color(0xFF050505);

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'GG Messenger',
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: black,
          colorScheme: ColorScheme.fromSeed(
            seedColor: gold,
            brightness: Brightness.dark,
          ),
          fontFamily: 'sans-serif',
        ),
        home: StreamBuilder<AuthState>(
          stream: Supabase.instance.client.auth.onAuthStateChange,
          builder: (_, __) => Supabase.instance.client.auth.currentSession == null
              ? const AuthPage()
              : const HomePage(),
        ),
      );
}

class GGLogo extends StatelessWidget {
  final double size;
  const GGLogo({super.key, this.size = 96});

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
        'assets/gg_messenger_logo.svg',
        width: size,
        height: size,
      );
}
