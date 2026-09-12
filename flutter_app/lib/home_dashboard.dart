import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'ai_page.dart';
import 'profile_page.dart';
import 'offline_home_page.dart';

class HomeDashboard extends StatelessWidget {
  const HomeDashboard({super.key});

  Future<void> _openProfile(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProfilePage()),
    );
  }

  Future<void> _openStudio(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AIPage()),
    );
  }

  Future<void> _openSettings(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _Settings(),
    );
  }

  Future<void> _logout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You can sign in again at any time.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await Supabase.instance.client.auth.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'GG Messenger',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        leading: IconButton(
          icon: const Icon(Icons.person),
          tooltip: 'Profile',
          onPressed: () => _openProfile(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Chat settings',
            onPressed: () => _openSettings(context),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'profile':
                  _openProfile(context);
                  break;
                case 'studio':
                  _openStudio(context);
                  break;
                case 'settings':
                  _openSettings(context);
                  break;
                case 'logout':
                  _logout(context);
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'profile',
                child: Text('Profile'),
              ),
              PopupMenuItem(
                value: 'studio',
                child: Text('AI • Image • Video • Music'),
              ),
              PopupMenuItem(
                value: 'settings',
                child: Text('Chat settings'),
              ),
              PopupMenuItem(
                value: 'logout',
                child: Text('Logout'),
              ),
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
                ActionChip(
                  avatar: const Icon(Icons.auto_awesome),
                  label: const Text('AI'),
                  onPressed: () => _openStudio(context),
                ),
                ActionChip(
                  avatar: const Icon(Icons.image),
                  label: const Text('Image'),
                  onPressed: () => _openStudio(context),
                ),
                ActionChip(
                  avatar: const Icon(Icons.video_library),
                  label: const Text('Video'),
                  onPressed: () => _openStudio(context),
                ),
                ActionChip(
                  avatar: const Icon(Icons.music_note),
                  label: const Text('Music'),
                  onPressed: () => _openStudio(context),
                ),
                ActionChip(
                  avatar: const Icon(Icons.person),
                  label: const Text('Profile'),
                  onPressed: () => _openProfile(context),
                ),
                ActionChip(
                  avatar: const Icon(Icons.settings),
                  label: const Text('Settings'),
                  onPressed: () => _openSettings(context),
                ),
                ActionChip(
                  avatar: const Icon(Icons.logout),
                  label: const Text('Logout'),
                  onPressed: () => _logout(context),
                ),
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
        const ListTile(
          title: Text(
            'Chat settings',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
        ),
        SwitchListTile(
          title: const Text('Notifications'),
          value: notifications,
          onChanged: (value) => setState(() => notifications = value),
        ),
        SwitchListTile(
          title: const Text('Dark mode'),
          value: dark,
          onChanged: (value) => setState(() => dark = value),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
