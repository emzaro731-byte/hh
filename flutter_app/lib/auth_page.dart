import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool signup = false;
  bool busy = false;
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();

  void snack(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> submit() async {
    if (email.text.trim().isEmpty || password.text.isEmpty || (signup && name.text.trim().isEmpty)) {
      snack('Complete all required fields.');
      return;
    }
    setState(() => busy = true);
    try {
      if (signup) {
        final result = await Supabase.instance.client.auth.signUp(
          email: email.text.trim(), password: password.text,
          data: {'display_name': name.text.trim()},
        );
        if (result.session == null) snack('Check your email to confirm your account.');
      } else {
        await Supabase.instance.client.auth.signInWithPassword(
          email: email.text.trim(), password: password.text,
        );
      }
    } catch (e) {
      snack(e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> reset() async {
    if (email.text.trim().isEmpty) {
      snack('Enter your email first.');
      return;
    }
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email.text.trim());
      snack('Password reset email sent.');
    } catch (e) {
      snack(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xff18140b), Color(0xff050505)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: const [BoxShadow(color: Color(0x55FFC83D), blurRadius: 30)],
                    ),
                    child: SvgPicture.asset('assets/gg_messenger_logo.svg', width: 110, height: 110),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'GG MESSENGER',
                    style: TextStyle(color: Color(0xffffd75a), fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 4),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    signup ? 'Create your account' : 'Welcome back',
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    signup ? 'Join GG Messenger and stay connected.' : 'Sign in to continue your conversations.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xffb7b0a0)),
                  ),
                  const SizedBox(height: 25),
                  if (signup) field(name, 'Display name'),
                  field(email, 'Email address', type: TextInputType.emailAddress),
                  field(password, 'Password', obscure: true),
                  if (!signup)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: reset,
                        child: const Text('Forgot password?', style: TextStyle(color: Color(0xffffd75a))),
                      ),
                    ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xffffc83d), foregroundColor: Colors.black),
                      onPressed: busy ? null : submit,
                      child: Text(
                        busy ? 'Please wait...' : (signup ? 'Create account' : 'Sign in'),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => signup = !signup),
                    child: Text(
                      signup ? 'Already have an account? Sign in' : 'New to GG? Create an account',
                      style: const TextStyle(color: Color(0xffffd75a)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget field(TextEditingController controller, String hint, {bool obscure = false, TextInputType? type}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: type,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xff8c877b)),
          filled: true,
          fillColor: const Color(0xff15130f),
          enabledBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: Color(0xff3c3527)),
            borderRadius: BorderRadius.circular(15),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: Color(0xffffc83d), width: 1.5),
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }
}
