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
    return Scaffold(
      appBar: AppBar(
        title: const Text('GG Messenger', style: TextStyle(fontWeight: FontWeight.w800)),
        leading: IconButton(
          icon: const Icon(Icons.person),
          tooltip: 'Profile',
          onPressed: () => _open(context, const ProfilePage()),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.camera_alt_outlined),
            tooltip: 'GG Status',
            onPressed: () => _open(context, const StatusPage()),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _settings(context),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'profile':
                  _open(context, const ProfilePage());
                  break;
                case 'status':
                  _open(context, const StatusPage());
                  break;
                case 'studio':
                  _open(context, const AIPage());
                  break;
                case 'settings':
                  _settings(context);
                  break;
                case 'logout':
                  _logout(context);
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'profile', child: Text('Profile')),
              PopupMenuItem(value: 'status', child: Text('GG Status')),
              PopupMenuItem(value: 'studio', child: Text('AI • Image • Video • Music')),
              PopupMenuItem(value: 'settings', child: Text('Chat settings')),
              PopupMenuItem(value: 'logout', child: Text('Logout')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(avatar: const Icon(Icons.camera_alt), label: const Text('Status'), onPressed: () => _open(context, const StatusPage())),
                ActionChip(avatar: const Icon(Icons.auto_awesome), label: const Text('AI'), onPressed: () => _open(context, const AIPage())),
                ActionChip(avatar: const Icon(Icons.image), label: const Text('Image'), onPressed: () => _open(context, const AIPage())),
                ActionChip(avatar: const Icon(Icons.video_library), label: const Text('Video'), onPressed: () => _open(context, const AIPage())),
                ActionChip(avatar: const Icon(Icons.music_note), label: const Text('Music'), onPressed: () => _open(context, const AIPage())),
                ActionChip(avatar: const Icon(Icons.person), label: const Text('Profile'), onPressed: () => _open(context, const ProfilePage())),
                ActionChip(avatar: const Icon(Icons.settings), label: const Text('Settings'), onPressed: () => _settings(context)),
              ],
            ),
          ),
          const Divider(height: 1),
          const Expanded(child: OfflineHomePage()),
        ],
      ),
    );
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const ListTile(title: Text('Chat settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
        SwitchListTile(title: const Text('Notifications'), value: notifications, onChanged: (value) => setState(() => notifications = value)),
        SwitchListTile(title: const Text('Dark mode'), value: dark, onChanged: (value) => setState(() => dark = value)),
        const SizedBox(height: 12),
      ],
    );
  }
}
