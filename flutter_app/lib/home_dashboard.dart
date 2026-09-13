import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'ai_page.dart';
import 'profile_page.dart';
import 'offline_home_page.dart';
import 'status_page.dart';

class HomeDashboard extends StatelessWidget {
  const HomeDashboard({super.key});

  Future<void> _open(BuildContext context, Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _settings(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => const _Settings(),
    );
  }

  Future<void> _logout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You can sign in again at any time.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Log out')),
        ],
      ),
    );
    if (ok == true) await Supabase.instance.client.auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    // The chat home owns its own premium navigation shell. Keeping one shell
    // avoids the old nested AppBar/Scaffold layout and gives the messenger a
    // cleaner, full-screen mobile experience.
    return const OfflineHomePage();
  }
}

class _Settings extends StatefulWidget {
  const _Settings();
  @override
  State<_Settings> createState() => _SettingsState();
}

class _SettingsState extends State<_Settings> {
  bool notifications = true;
  bool dark = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(title: Text('Chat settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
          SwitchListTile(title: const Text('Notifications'), value: notifications, onChanged: (value) => setState(() => notifications = value)),
          SwitchListTile(title: const Text('Dark mode'), value: dark, onChanged: (value) => setState(() => dark = value)),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
