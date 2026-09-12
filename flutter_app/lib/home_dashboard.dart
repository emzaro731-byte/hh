import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'ai_page.dart';
import 'profile_page.dart';
import 'offline_home_page.dart';

class HomeDashboard extends StatelessWidget {
  const HomeDashboard({super.key});
  void studio(BuildContext c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const AIPage()));
  void profile(BuildContext c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const ProfilePage()));
  void settings(BuildContext c) => showModalBottomSheet(context: c, showDragHandle: true, builder: (_) => const _Settings());
  Future<void> logout(BuildContext c) async { final yes = await showDialog<bool>(context: c, builder: (_) => AlertDialog(title: const Text('Log out?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Log out'))])); if (yes == true) await Supabase.instance.client.auth.signOut(); }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('GG Messenger', style: TextStyle(fontWeight: FontWeight.w800)), leading: IconButton(icon: const Icon(Icons.person), onPressed: () => profile(context)), actions: [IconButton(icon: const Icon(Icons.settings_outlined), onPressed: () => settings(context)), PopupMenuButton<String>(onSelected: (v) { if (v == 'profile') profile(context); if (v == 'studio') studio(context); if (v == 'settings') settings(context); if (v == 'logout') logout(context); }, itemBuilder: (_) => const [PopupMenuItem(value:'profile', child: Text('Profile')), PopupMenuItem(value:'studio', child: Text('AI • Image • Video • Music')), PopupMenuItem(value:'settings', child: Text('Chat settings')), PopupMenuItem(value:'logout', child: Text('Logout'))])]),
    body: Column(children: [Padding(padding: const EdgeInsets.all(12), child: Wrap(spacing: 8, runSpacing: 8, children: [ActionChip(avatar: const Icon(Icons.auto_awesome), label: const Text('AI'), onPressed: () => studio(context)), ActionChip(avatar: const Icon(Icons.image), label: const Text('Image'), onPressed: () => studio(context)), ActionChip(avatar: const Icon(Icons.video_library), label: const Text('Video'), onPressed: () => studio(context)), ActionChip(avatar: const Icon(Icons.music_note), label: const Text('Music'), onPressed: () => studio(context)), ActionChip(avatar: const Icon(Icons.person), label: const Text('Profile'), onPressed: () => profile(context)), ActionChip(avatar: const Icon(Icons.settings), label: const Text('Settings'), onPressed: () => settings(context)), ActionChip(avatar: const Icon(Icons.logout), label: const Text('Logout'), onPressed: () => logout(context))])), const Divider(height: 1), const Expanded(child: OfflineHomePage())]),
  );
}
class _Settings extends StatefulWidget { const _Settings(); @override State<_Settings> createState() => _SettingsState(); }
class _SettingsState extends State<_Settings> { bool notifications = true, dark = false; @override Widget build(BuildContext c) => Column(mainAxisSize: MainAxisSize.min, children: [const ListTile(title: Text('Chat settings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))), SwitchListTile(title: const Text('Notifications'), value: notifications, onChanged: (v) => setState(() => notifications = v)), SwitchListTile(title: const Text('Dark mode'), value: dark, onChanged: (v) => setState(() => dark = v)), const SizedBox(height: 12)]); }
