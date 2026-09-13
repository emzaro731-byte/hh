import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'offline_store.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final sb = Supabase.instance.client;
  final picker = ImagePicker();
  final name = TextEditingController();
  final username = TextEditingController();
  final bio = TextEditingController();
  String? avatarUrl;
  bool loading = true, saving = false;

  @override void initState() { super.initState(); _load(); }
  @override void dispose() { name.dispose(); username.dispose(); bio.dispose(); super.dispose(); }

  Future<void> _load() async {
    final u = sb.auth.currentUser;
    if (u == null) return;

    // Show the last known profile immediately, even with no connection.
    final cached = await OfflineStore.loadData(u.id, 'profile');
    if (cached is Map && mounted) {
      name.text = '${cached['display_name'] ?? ''}';
      username.text = '${cached['username'] ?? ''}';
      bio.text = '${cached['bio'] ?? ''}';
      avatarUrl = cached['avatar_url']?.toString();
      setState(() => loading = false);
    }

    try {
      final p = await sb.from('profiles').select('display_name,username,bio,avatar_url').eq('id', u.id).maybeSingle();
      if (p != null) {
        name.text = '${p['display_name'] ?? ''}';
        username.text = '${p['username'] ?? ''}';
        bio.text = '${p['bio'] ?? ''}';
        avatarUrl = p['avatar_url']?.toString();
        await OfflineStore.saveData(u.id, 'profile', p);
      }
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<void> _pickAvatar() async {
    final x = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1000);
    if (x == null) return;
    final u = sb.auth.currentUser; if (u == null) return;
    setState(() => saving = true);
    try {
      final bytes = await x.readAsBytes();
      final path = '${u.id}/avatar.jpg';
      await sb.storage.from('avatars').uploadBinary(path, bytes, fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true));
      final url = sb.storage.from('avatars').getPublicUrl(path);
      await sb.from('profiles').upsert({'id': u.id, 'avatar_url': url});
      avatarUrl = url;
      await _cacheProfile();
      if (mounted) setState(() {});
    } catch (e) { if (mounted) _snack('Avatar upload failed: $e'); }
    if (mounted) setState(() => saving = false);
  }

  Future<void> _cacheProfile() async {
    final u = sb.auth.currentUser;
    if (u == null) return;
    await OfflineStore.saveData(u.id, 'profile', {
      'display_name': name.text.trim(),
      'username': username.text.trim(),
      'bio': bio.text.trim(),
      'avatar_url': avatarUrl,
    });
  }

  Future<void> _save() async {
    final u = sb.auth.currentUser; if (u == null) return;
    setState(() => saving = true);
    final local = {
      'display_name': name.text.trim().isEmpty ? 'GG User' : name.text.trim(),
      'username': username.text.trim().isEmpty ? null : username.text.trim(),
      'bio': bio.text.trim(),
      'avatar_url': avatarUrl,
    };
    // Save locally first so edits are not lost if the connection disappears.
    await OfflineStore.saveData(u.id, 'profile', local);
    try {
      await sb.from('profiles').upsert({'id': u.id, ...local});
      if (mounted) { _snack('Profile saved'); Navigator.pop(context, true); }
    } catch (_) {
      if (mounted) _snack('Saved offline. It will remain on this device.');
    }
    if (mounted) setState(() => saving = false);
  }

  void _snack(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  @override Widget build(BuildContext context) {
    final fallback = name.text.trim().isEmpty ? 'G' : name.text.trim()[0].toUpperCase();
    return Scaffold(appBar: AppBar(title: const Text('Profile', style: TextStyle(fontWeight: FontWeight.w800))), body: loading ? const Center(child: CircularProgressIndicator()) : ListView(padding: const EdgeInsets.all(20), children: [
      Center(child: Stack(children: [CircleAvatar(radius: 58, backgroundImage: avatarUrl != null && avatarUrl!.isNotEmpty ? NetworkImage(avatarUrl!) : null, child: avatarUrl == null || avatarUrl!.isEmpty ? Text(fallback, style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800)) : null), Positioned(right: 0, bottom: 0, child: FloatingActionButton.small(onPressed: saving ? null : _pickAvatar, child: const Icon(Icons.camera_alt)))])),
      const SizedBox(height: 10), Center(child: Text('Tap the camera to change your profile picture', style: Theme.of(context).textTheme.bodySmall)),
      const SizedBox(height: 24),
      TextField(controller: name, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Display name', prefixIcon: Icon(Icons.person_outline), border: OutlineInputBorder())),
      const SizedBox(height: 14), TextField(controller: username, decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.alternate_email), border: OutlineInputBorder())),
      const SizedBox(height: 14), TextField(controller: bio, maxLines: 3, decoration: const InputDecoration(labelText: 'Bio', prefixIcon: Icon(Icons.info_outline), border: OutlineInputBorder())),
      const SizedBox(height: 24), SizedBox(height: 52, child: FilledButton.icon(onPressed: saving ? null : _save, icon: const Icon(Icons.save), label: Text(saving ? 'Saving...' : 'Save profile'))),
    ]));
  }
}
