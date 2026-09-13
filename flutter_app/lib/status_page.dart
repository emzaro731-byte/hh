import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'offline_store.dart';

const _bg = Color(0xff080b0f);
const _surface = Color(0xff11161a);
const _green = Color(0xff20d76b);

class StatusPage extends StatefulWidget {
  const StatusPage({super.key});

  @override
  State<StatusPage> createState() => _StatusPageState();
}

class _StatusPageState extends State<StatusPage> {
  final SupabaseClient sb = Supabase.instance.client;
  final ImagePicker picker = ImagePicker();

  bool loading = true;
  bool posting = false;
  int tab = 1;
  List<Map<String, dynamic>> statuses = <Map<String, dynamic>>[];
  Map<String, Map<String, dynamic>> profiles = <String, Map<String, dynamic>>{};
  Set<String> viewed = <String>{};

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final me = sb.auth.currentUser?.id;
    if (mounted) setState(() => loading = true);

    // Render the last known updates immediately. This keeps the screen useful offline.
    if (me != null) {
      final cached = await OfflineStore.loadData(me, 'statuses');
      final cachedProfiles = await OfflineStore.loadData(me, 'status_profiles');
      final cachedViewed = await OfflineStore.loadData(me, 'status_viewed');
      if (cached is List && mounted) {
        statuses = cached.map((x) => Map<String, dynamic>.from(x as Map)).toList();
        if (cachedProfiles is Map) {
          profiles = cachedProfiles.map((key, value) => MapEntry(
                key.toString(),
                Map<String, dynamic>.from(value as Map),
              ));
        }
        if (cachedViewed is List) viewed = cachedViewed.map((x) => x.toString()).toSet();
        setState(() => loading = false);
      }
    }

    try {
      final rows = await sb
          .from('statuses')
          .select('id,user_id,type,text,media_url,background,created_at,expires_at')
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .order('created_at', ascending: false);

      statuses = List<Map<String, dynamic>>.from(rows);

      final ids = statuses
          .map((Map<String, dynamic> row) => row['user_id'].toString())
          .toSet()
          .toList();

      if (ids.isNotEmpty) {
        final rows = await sb
            .from('profiles')
            .select('id,display_name,username,avatar_url')
            .inFilter('id', ids);

        profiles = <String, Map<String, dynamic>>{
          for (final profile in List<Map<String, dynamic>>.from(rows))
            profile['id'].toString(): profile,
        };
      }

      if (me != null) {
        final rows = await sb
            .from('status_views')
            .select('status_id')
            .eq('viewer_id', me);

        viewed = {
          for (final row in List<Map<String, dynamic>>.from(rows))
            row['status_id'].toString(),
        };

        await OfflineStore.saveData(me, 'statuses', statuses);
        await OfflineStore.saveData(me, 'status_profiles', profiles);
        await OfflineStore.saveData(me, 'status_viewed', viewed.toList());
      }
    } catch (e) {
      // Cached data stays on screen when there is no connection.
      if (statuses.isEmpty && mounted) _snack('No offline updates available.');
    }

    if (mounted) setState(() => loading = false);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String displayName(String id) {
    final value = profiles[id]?['display_name']?.toString().trim();
    return value == null || value.isEmpty ? 'GG User' : value;
  }

  String avatarUrl(String id) => profiles[id]?['avatar_url']?.toString() ?? '';

  Future<void> createText() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New status'),
        content: TextField(controller: controller, maxLines: 5, autofocus: true, decoration: const InputDecoration(hintText: 'What is happening?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Post')),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.isEmpty) return;
    try {
      final user = sb.auth.currentUser;
      if (user == null) { _snack('Please sign in first.'); return; }
      await sb.from('statuses').insert(<String, dynamic>{'user_id': user.id, 'type': 'text', 'text': text, 'background': '2563eb'});
      await load();
    } catch (e) { _snack('Could not post: $e'); }
  }

  Future<void> pickMedia(bool video) async {
    final XFile? file = video ? await picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 1)) : await picker.pickImage(source: ImageSource.gallery, imageQuality: 88, maxWidth: 1600);
    if (file == null) return;
    if (mounted) setState(() => posting = true);
    try {
      final user = sb.auth.currentUser;
      if (user == null) { _snack('Please sign in first.'); return; }
      final extension = file.path.contains('.') ? file.path.split('.').last.toLowerCase() : (video ? 'mp4' : 'jpg');
      final path = '${user.id}/${DateTime.now().microsecondsSinceEpoch}.$extension';
      await sb.storage.from('status-media').uploadBinary(path, await file.readAsBytes(), fileOptions: FileOptions(upsert: false, contentType: video ? 'video/mp4' : 'image/jpeg'));
      final url = await sb.storage.from('status-media').createSignedUrl(path, 86400);
      await sb.from('statuses').insert(<String, dynamic>{'user_id': user.id, 'type': video ? 'video' : 'image', 'media_url': url});
      await load();
    } catch (e) { _snack('Upload failed: $e'); }
    finally { if (mounted) setState(() => posting = false); }
  }

  Future<void> openStatus(Map<String, dynamic> status) async {
    final me = sb.auth.currentUser?.id;
    final owner = status['user_id']?.toString();
    if (me != null && owner != null && me != owner) {
      try {
        await sb.from('status_views').upsert(<String, dynamic>{'status_id': status['id'], 'viewer_id': me});
        viewed.add(status['id'].toString());
        await OfflineStore.saveData(me, 'status_viewed', viewed.toList());
      } catch (_) {}
    }
    if (!mounted) return;
    await Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => _StatusViewer(status: status, profile: owner == null ? <String, dynamic>{} : profiles[owner] ?? {}, sb: sb)));
    await load();
  }

  @override
  Widget build(BuildContext context) {
    final me = sb.auth.currentUser?.id;
    final mine = statuses.where((s) => s['user_id']?.toString() == me).toList();
    final grouped = <String, Map<String, dynamic>>{};
    for (final status in statuses) {
      final owner = status['user_id']?.toString();
      if (owner != null && owner != me) grouped.putIfAbsent(owner, () => status);
    }
    final updates = grouped.values.toList();
    return Theme(
      data: ThemeData.dark(useMaterial3: true).copyWith(scaffoldBackgroundColor: _bg, colorScheme: ColorScheme.fromSeed(seedColor: _green, brightness: Brightness.dark), appBarTheme: const AppBarTheme(backgroundColor: _bg, foregroundColor: Colors.white, elevation: 0)),
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(title: const Text('Updates', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)), actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh, size: 28)), PopupMenuButton<String>(onSelected: (_) {}, itemBuilder: (_) => const [PopupMenuItem(value: 'settings', child: Text('Updates settings'))])]),
        body: loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(color: _green, onRefresh: load, child: ListView(padding: const EdgeInsets.only(bottom: 18), children: [
          const Padding(padding: EdgeInsets.fromLTRB(30, 4, 24, 12), child: Text('Status', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800))),
          SizedBox(height: 260, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 30), children: [
            _AddStatusCard(onTap: createText, onMediaTap: () => pickMedia(false), image: mine.isNotEmpty ? _mediaUrl(mine.first) : null),
            ...updates.take(8).map((status) => _StatusCard(status: status, name: displayName(status['user_id'].toString()), avatarUrl: avatarUrl(status['user_id'].toString()), unread: !viewed.contains(status['id'].toString()), onTap: () => openStatus(status))),
          ])),
          const Padding(padding: EdgeInsets.fromLTRB(30, 26, 24, 8), child: Text('Channels', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800))),
          Padding(padding: const EdgeInsets.only(right: 30), child: Align(alignment: Alignment.centerRight, child: FilledButton(onPressed: () => _snack('Channel discovery coming soon'), style: FilledButton.styleFrom(backgroundColor: _surface, foregroundColor: Colors.white), child: const Text('Explore', style: TextStyle(fontWeight: FontWeight.w800))))),
          const SizedBox(height: 8),
          if (updates.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('No channel updates yet', style: TextStyle(color: Colors.white70, fontSize: 16)))),
          ...updates.take(10).map((status) => _ChannelRow(status: status, name: displayName(status['user_id'].toString()), avatarUrl: avatarUrl(status['user_id'].toString()), onTap: () => openStatus(status))),
        ])),
        bottomNavigationBar: NavigationBar(backgroundColor: const Color(0xff090d11), indicatorColor: const Color(0xff073e2a), selectedIndex: tab, onDestinationSelected: (index) { if (index == 0) { Navigator.pop(context); return; } setState(() => tab = index); if (index == 2 || index == 3) _snack(index == 2 ? 'Communities' : 'Calls'); }, destinations: const [NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Chats'), NavigationDestination(icon: Icon(Icons.circle_outlined), selectedIcon: Icon(Icons.circle, color: _green), label: 'Updates'), NavigationDestination(icon: Icon(Icons.groups_outlined), label: 'Communities'), NavigationDestination(icon: Icon(Icons.call_outlined), label: 'Calls')]),
        floatingActionButton: posting ? const FloatingActionButton(onPressed: null, child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))) : FloatingActionButton(backgroundColor: _green, foregroundColor: Colors.black, onPressed: () => pickMedia(false), child: const Icon(Icons.camera_alt)),
      ),
    );
  }

  String? _mediaUrl(Map<String, dynamic> status) => status['type'] == 'image' ? status['media_url']?.toString() : null;
}

class _AddStatusCard extends StatelessWidget {
  final VoidCallback onTap; final VoidCallback onMediaTap; final String? image;
  const _AddStatusCard({required this.onTap, required this.onMediaTap, this.image});
  @override Widget build(BuildContext context) => GestureDetector(onTap: onTap, child: Container(width: 145, margin: const EdgeInsets.only(right: 14), decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white12)), child: Stack(fit: StackFit.expand, children: [ClipRRect(borderRadius: BorderRadius.circular(23), child: image != null && image!.isNotEmpty ? Image.network(image!, fit: BoxFit.cover) : const ColoredBox(color: Color(0xff172025))), Align(alignment: Alignment.bottomLeft, child: Container(height: 100, decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87])))), const Positioned(left: 16, bottom: 14, child: Text('Add status', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))), Positioned(left: 14, bottom: 62, child: GestureDetector(onTap: onMediaTap, child: const CircleAvatar(backgroundColor: _green, radius: 20, child: Icon(Icons.add, color: Colors.black, size: 28))))])));
}

class _StatusCard extends StatelessWidget {
  final Map<String, dynamic> status; final String name; final String avatarUrl; final bool unread; final VoidCallback onTap;
  const _StatusCard({required this.status, required this.name, required this.avatarUrl, required this.unread, required this.onTap});
  @override Widget build(BuildContext context) => GestureDetector(onTap: onTap, child: Container(width: 145, margin: const EdgeInsets.only(right: 14), decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(24), border: Border.all(color: unread ? _green : Colors.white12, width: unread ? 2 : 1)), child: Stack(fit: StackFit.expand, children: [ClipRRect(borderRadius: BorderRadius.circular(23), child: status['type'] == 'image' && (status['media_url']?.toString().isNotEmpty ?? false) ? Image.network(status['media_url'].toString(), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xff172025))) : ColoredBox(color: Color(int.tryParse('0xff${status['background'] ?? '172025'}') ?? 0xff172025))), Align(alignment: Alignment.bottomLeft, child: Container(height: 90, decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87])))), Positioned(left: 12, bottom: 12, right: 8, child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white))), Positioned(left: 10, top: 10, child: CircleAvatar(radius: 20, backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null, child: avatarUrl.isEmpty ? Text(name.isEmpty ? 'G' : name[0]) : null))]));
}

class _ChannelRow extends StatelessWidget {
  final Map<String, dynamic> status; final String name; final String avatarUrl; final VoidCallback onTap;
  const _ChannelRow({required this.status, required this.name, required this.avatarUrl, required this.onTap});
  @override Widget build(BuildContext context) => ListTile(onTap: onTap, leading: CircleAvatar(backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null, child: avatarUrl.isEmpty ? Text(name.isEmpty ? 'G' : name[0]) : null), title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(status['text']?.toString().isNotEmpty == true ? status['text'].toString() : 'Update'), trailing: const Icon(Icons.chevron_right));
}

String _statusMediaPlaceholder(Map<String, dynamic> status) => status['media_url']?.toString() ?? '';

class _StatusViewer extends StatelessWidget {
  final Map<String, dynamic> status; final Map<String, dynamic> profile; final SupabaseClient sb;
  const _StatusViewer({required this.status, required this.profile, required this.sb});
  @override Widget build(BuildContext context) => Scaffold(backgroundColor: Colors.black, appBar: AppBar(title: Text(profile['display_name']?.toString() ?? 'GG User')), body: Center(child: status['type'] == 'text' ? Padding(padding: const EdgeInsets.all(30), child: Text(status['text']?.toString() ?? '', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700))) : (status['media_url']?.toString().isNotEmpty ?? false) ? Image.network(status['media_url'].toString(), fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Text('Media unavailable offline', style: TextStyle(color: Colors.white70))) : const Text('Media unavailable offline', style: TextStyle(color: Colors.white70))));
}
