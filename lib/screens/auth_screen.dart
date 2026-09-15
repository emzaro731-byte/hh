import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _redirectUrl = 'veylola://auth-callback';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _register = false, _forgot = false, _busy = false, _hide = true;
  SupabaseClient get _supabase => Supabase.instance.client;
  @override void dispose() { _email.dispose(); _password.dispose(); _confirm.dispose(); super.dispose(); }
  Future<void> _submit() async {
    final email = _email.text.trim(), password = _password.text;
    if (email.isEmpty || (!_forgot && password.length < 6)) { _message('Enter a valid email and a password of at least 6 characters.'); return; }
    if (_register && password != _confirm.text) { _message('Passwords do not match.'); return; }
    setState(() => _busy = true);
    try {
      if (_forgot) { await _supabase.auth.resetPasswordForEmail(email, redirectTo: _redirectUrl); _message('Password reset email sent. Check your inbox.'); if (mounted) setState(() => _forgot = false); }
      else if (_register) { final response = await _supabase.auth.signUp(email: email, password: password, emailRedirectTo: _redirectUrl); if (response.session == null) _message('Account created. Check your email to confirm your account.'); }
      else await _supabase.auth.signInWithPassword(email: email, password: password);
    } on AuthException catch (e) { _message(e.message); } catch (e) { _message('Authentication failed: $e'); } finally { if (mounted) setState(() => _busy = false); }
  }
  void _message(String text) { if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating)); }
  @override Widget build(BuildContext context) {
    final title = _forgot ? 'Reset password' : (_register ? 'Create account' : 'Welcome back');
    return Scaffold(backgroundColor: const Color(0xFF070A10), body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 430), child: Column(children: [
      Container(width: 78, height: 78, decoration: BoxDecoration(shape: BoxShape.circle, gradient: const LinearGradient(colors: [Color(0xFFB35CFF), Color(0xFF3E9BFF)]), boxShadow: [BoxShadow(color: const Color(0xFF765CFF).withOpacity(.35), blurRadius: 35)]), child: const Icon(Icons.auto_awesome, size: 38)),
      const SizedBox(height: 18), const Text('VEYLOLA', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900)), const SizedBox(height: 6), Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)), const SizedBox(height: 26),
      _field(_email, 'Email address', Icons.email_outlined, false), if (!_forgot) ...[const SizedBox(height: 12), _field(_password, 'Password', Icons.lock_outline, true), if (_register) ...[const SizedBox(height: 12), _field(_confirm, 'Confirm password', Icons.lock_reset_outlined, true)]], const SizedBox(height: 18),
      SizedBox(width: double.infinity, child: FilledButton(onPressed: _busy ? null : _submit, style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(_forgot ? 'Send reset link' : (_register ? 'Create account' : 'Sign in')))),
      const SizedBox(height: 10), if (!_forgot && !_register) TextButton(onPressed: () => setState(() => _forgot = true), child: const Text('Forgot password?')), if (!_forgot) TextButton(onPressed: () => setState(() => _register = !_register), child: Text(_register ? 'Already have an account? Sign in' : 'New to VEYLOLA? Create an account')), if (_forgot) TextButton(onPressed: () => setState(() => _forgot = false), child: const Text('Back to sign in')), const SizedBox(height: 16), const Text('Your account and session are secured by Supabase Auth.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 12)),
    ]))))));
  }
  Widget _field(TextEditingController controller, String hint, IconData icon, bool password) => TextField(controller: controller, obscureText: password && _hide, keyboardType: hint.contains('Email') ? TextInputType.emailAddress : TextInputType.visiblePassword, decoration: InputDecoration(prefixIcon: Icon(icon), hintText: hint, filled: true, fillColor: const Color(0xFF121722), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none), suffixIcon: password ? IconButton(onPressed: () => setState(() => _hide = !_hide), icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined)) : null));
}

class UpdatePasswordScreen extends StatefulWidget { const UpdatePasswordScreen({super.key}); @override State<UpdatePasswordScreen> createState() => _UpdatePasswordScreenState(); }
class _UpdatePasswordScreenState extends State<UpdatePasswordScreen> {
  final _password = TextEditingController(), _confirm = TextEditingController(); bool _busy = false;
  @override void dispose() { _password.dispose(); _confirm.dispose(); super.dispose(); }
  Future<void> _update() async { if (_password.text.length < 6 || _password.text != _confirm.text) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Use matching passwords with at least 6 characters.'))); return; } setState(() => _busy = true); try { await Supabase.instance.client.auth.updateUser(UserAttributes(password: _password.text)); if (mounted) Navigator.of(context).pop(); } on AuthException catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message))); } finally { if (mounted) setState(() => _busy = false); } }
  @override Widget build(BuildContext context) => Scaffold(backgroundColor: const Color(0xFF070A10), appBar: AppBar(title: const Text('Set new password')), body: Padding(padding: const EdgeInsets.all(24), child: Column(children: [TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'New password', prefixIcon: Icon(Icons.lock_outline))), const SizedBox(height: 14), TextField(controller: _confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm password', prefixIcon: Icon(Icons.lock_reset_outlined))), const SizedBox(height: 22), SizedBox(width: double.infinity, child: FilledButton(onPressed: _busy ? null : _update, child: _busy ? const CircularProgressIndicator() : const Text('Update password')))]));
}
