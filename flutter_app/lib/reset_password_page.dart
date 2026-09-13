import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final password = TextEditingController();
  final confirm = TextEditingController();
  bool busy = false;
  bool obscure = true;

  void snack(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> updatePassword() async {
    if (password.text.length < 6) {
      snack('Password must be at least 6 characters.');
      return;
    }
    if (password.text != confirm.text) {
      snack('Passwords do not match.');
      return;
    }
    setState(() => busy = true);
    try {
      await Supabase.instance.client.auth.updateUser(UserAttributes(password: password.text));
      if (mounted) {
        snack('Password updated successfully.');
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      snack(e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Create a new password', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              const Text('Choose a new password for your GG Messenger account.'),
              const SizedBox(height: 24),
              TextField(
                controller: password,
                obscureText: obscure,
                decoration: InputDecoration(labelText: 'New password', border: const OutlineInputBorder(), suffixIcon: IconButton(onPressed: () => setState(() => obscure = !obscure), icon: Icon(obscure ? Icons.visibility : Icons.visibility_off))),
              ),
              const SizedBox(height: 12),
              TextField(controller: confirm, obscureText: obscure, decoration: const InputDecoration(labelText: 'Confirm new password', border: OutlineInputBorder())),
              const SizedBox(height: 20),
              FilledButton(onPressed: busy ? null : updatePassword, child: Text(busy ? 'Updating...' : 'Update password')),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    password.dispose();
    confirm.dispose();
    super.dispose();
  }
}
