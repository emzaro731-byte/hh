import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _bg = Color(0xff080b0f);
const _surface = Color(0xff11161a);
const _green = Color(0xff20d76b);

class StatusPage extends StatefulWidget {
  const StatusPage({super.key});
  @override State<StatusPage> createState() => _StatusPageState();
}

class _StatusPageState extends State<StatusPage> {
  final sb = Supabase.instance.client;
  final picker = ImagePicker();
  bool loading = true, posting = false;
  int tab = 1;
  List<Map<String, dynamic>> statuses = [];
  Map<String, Map<String, dynamic>> profiles = {};
  Set<String> viewed = {};

  @override void initState() { super.initState(); load(); }

  Future<void> load() async {
    if (mounted) setState(() => loading = true);
    try {
      final rows = await sb.from('statuses').select('id,user_id,type,text,media_url,background,created_at,expires_at').gt('expires_at', DateTime.now().toUtc().toIso8601String()).order('created_at', ascending: false);
      statuses = List<Map<String, dynamic>>.from(rows);
      final ids = statuses.map((e) => e['user_id'].toString()).toSet().toList();
      if (ids.isNotEmpty) {
        final ps = await sb.from('profiles').select('id,display_name,username,avatar_url').inFilter('id', ids);
        profiles = {for (final p in List<Map<String, dynamic>>.from(ps)) p['id'].toString(): p};
      }
      final me = sb.auth.currentUser?.id;
      if (me != null) {
        final v = await sb.from('status_views').select('status_id').eq('viewer_id', me);
        viewed = {for (final x in List<Map<String, dynamic>>.from(v)) x['status_id'].toString()};
      }
    } catch (e) { if (mounted) _snack('Could not load updates: $e'); }
    if (mounted) setState(() => loading = false);
  }

  void _snack(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  String name(String id) => (profiles[id]?['display_name']?.toString().trim().isNotEmpty == true) ? profiles[id]!['display_name'].toString() : 'GG User';
  String avatar(String id) => profiles[id]?['avatar_url']?.toString() ?? '';

  Future<void> createText() async {
    final c = TextEditingController();
    final text = await showDialog<String>(context: context, builder: (d) => AlertDialog(title: const Text('New status'), content: TextField(controller: c, maxLines: 5, autofocus: true, decoration: const InputDecoration(hintText: 'What is happening?')), actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Post'))]));
    c.dispose();
    if (text == null || text.isEmpty) return;
    try { await sb.from('statuses').insert({'user_id': sb.auth.currentUser!.id, 'type': 'text', 'text': text, 'background': '2563eb'}); await load(); } catch (e) { _snack('Could not post: $e'); }
  }

  Future<void> pickMedia(bool video) async {
    final XFile? file = video ? await picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 1)) : await picker.pickImage(source: ImageSource.gallery, imageQuality: 88, maxWidth: 1600);
    if (file == null) return;
    setState(() => posting = true);
    try {
      final uid = sb.auth.currentUser!.id;
      final ext = file.path.contains('.') ? file.path.split('.').last.toLowerCase() : (video ? 'mp4' : 'jpg');
      final path = '$uid/${DateTime.now().microsecondsSinceEpoch}.$ext';
      await sb.storage.from('status-media').uploadBinary(path, await file.readAsBytes(), fileOptions: FileOptions(upsert: false, contentType: video ? 'video/mp4' : 'image/jpeg'));
      final url = await sb.storage.from('status-media').createSignedUrl(path, 86400);
      await sb.from('statuses').insert({'user_id': uid, 'type': video ? 'video' : 'image', 'media_url': url});
      await load();
    } catch (e) { _snack('Upload failed: $e'); }
    if (mounted) setState(() => posting = false);
  }

  Future<void> openStatus(Map<String, dynamic> s) async {
    final me = sb.auth.currentUser?.id;
    if (me != null && me != s['user_id']) {
      try { await sb.from('status_views').upsert({'status_id': s['id'], 'viewer_id': me}); viewed.add(s['id'].toString()); } catch (_) {}
    }
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => _StatusViewer(status: s, profile: profiles[s['user_id'].toString()] ?? {}, sb: sb)));
    load();
  }

  @override Widget build(BuildContext context) {
    final me = sb.auth.currentUser?.id;
    final mine = statuses.where((s) => s['user_id'] == me).toList();
    final grouped = <String, Map<String, dynamic>>{};
    for (final s in statuses.where((s) => s['user_id'] != me)) { grouped.putIfAbsent(s['user_id'].toString(), () => s); }
    final updates = grouped.values.toList();
    return Theme(
      data: ThemeData.dark(useMaterial3: true).copyWith(scaffoldBackgroundColor: _bg, colorScheme: ColorScheme.fromSeed(seedColor: _green, brightness: Brightness.dark), appBarTheme: const AppBarTheme(backgroundColor: _bg, foregroundColor: Colors.white, elevation: 0)),
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(title: const Text('Updates', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)), actions: [IconButton(onPressed: load, icon: const Icon(Icons.search, size: 30)), PopupMenuButton<String>(onSelected: (_) {}, itemBuilder: (_) => const [PopupMenuItem(value: 'settings', child: Text('Updates settings'))])]),
        body: loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(color: _green, onRefresh: load, child: ListView(padding: const EdgeInsets.only(bottom: 18), children: [
          const Padding(padding: EdgeInsets.fromLTRB(30, 4, 24, 12), child: Text('Status', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800))),
          SizedBox(height: 260, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 30), children: [
            _AddStatusCard(onTap: createText, image: mine.isNotEmpty ? _mediaUrl(mine.first) : null),
            ...updates.take(8).map((s) => _StatusCard(status: s, name: name(s['user_id'].toString()), avatarUrl: avatar(s['user_id'].toString()), unread: !viewed.contains(s['id'].toString()), onTap: () => openStatus(s))),
          ])),
          const Padding(padding: EdgeInsets.fromLTRB(30, 26, 24, 8), child: Text('Channels', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800))),
          Padding(padding: const EdgeInsets.only(right: 30), child: Align(alignment: Alignment.centerRight, child: FilledButton(onPressed: () => _snack('Channel discovery coming soon'), style: FilledButton.styleFrom(backgroundColor: _surface, foregroundColor: Colors.white), child: const Text('Explore', style: TextStyle(fontWeight: FontWeight.w800))))),
          const SizedBox(height: 8),
          if (updates.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('No channel updates yet', style: TextStyle(color: Colors.white70, fontSize: 16)))),
          ...updates.take(10).map((s) => _ChannelRow(status: s, name: name(s['user_id'].toString()), avatarUrl: avatar(s['user_id'].toString()), onTap: () => openStatus(s))),
        ])),
        bottomNavigationBar: NavigationBar(backgroundColor: const Color(0xff090d11), indicatorColor: const Color(0xff073e2a), selectedIndex: tab, onDestinationSelected: (i) { if (i == 0) { Navigator.pop(context); return; } setState(() => tab = i); if (i == 2 || i == 3) _snack(i == 2 ? 'Communities' : 'Calls'); }, destinations: const [NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Chats'), NavigationDestination(icon: Icon(Icons.circle_outlined), selectedIcon: Icon(Icons.circle, color: _green), label: 'Updates'), NavigationDestination(icon: Icon(Icons.groups_outlined), label: 'Communities'), NavigationDestination(icon: Icon(Icons.call_outlined), label: 'Calls')]),
        floatingActionButton: FloatingActionButton(backgroundColor: _green, foregroundColor: Colors.black, onPressed: () => pickMedia(false), child: const Icon(Icons.camera_alt)),
      ),
    );
  }

  String? _mediaUrl(Map<String, dynamic> s) => s['type'] == 'image' ? s['media_url']?.toString() : null;
}

class _AddStatusCard extends StatelessWidget {
  final VoidCallback onTap; final String? image;
  const _AddStatusCard({required this.onTap, this.image});
  @override Widget build(BuildContext context) => GestureDetector(onTap: onTap, child: Container(width: 145, margin: const EdgeInsets.only(right: 14), decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white12)), child: Stack(fit: StackFit.expand, children: [ClipRRect(borderRadius: BorderRadius.circular(23), child: image != null && image!.isNotEmpty ? Image.network(image!, fit: BoxFit.cover) : const ColoredBox(color: Color(0xff172025))), Align(alignment: Alignment.bottomLeft, child: Container(height: 100, decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87])))), const Positioned(left: 16, bottom: 14, child: Text('Add status', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))), const Positioned(left: 14, bottom: 62, child: CircleAvatar(backgroundColor: _green, radius: 20, child: Icon(Icons.add, color: Colors.black, size: 28)))])));
}

class _StatusCard extends StatelessWidget {
  final Map<String, dynamic> status; final String name, avatarUrl; final bool unread; final VoidCallback onTap;
  const _StatusCard({required this.status, required this.name, required this.avatarUrl, required this.unread, required this.onTap});
  @override Widget build(BuildContext context) => GestureDetector(onTap: onTap, child: Container(width: 145, margin: const EdgeInsets.only(right: 14), decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white12)), child: Stack(fit: StackFit.expand, children: [ClipRRect(borderRadius: BorderRadius.circular(23), child: _Thumb(status: status)), Positioned(top: 10, left: 10, child: _RingAvatar(url: avatarUrl, unread: unread, radius: 28)), Align(alignment: Alignment.bottomLeft, child: Container(height: 92, decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87])))), Positioned(left: 14, bottom: 14, right: 8, child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)))])));
}

class _ChannelRow extends StatelessWidget {
  final Map<String, dynamic> status; final String name, avatarUrl; final VoidCallback onTap;
  const _ChannelRow({required this.status, required this.name, required this.avatarUrl, required this.onTap});
  @override Widget build(BuildContext context) => InkWell(onTap: onTap, child: Padding(padding: const EdgeInsets.fromLTRB(30, 12, 30, 12), child: Row(children: [
    _RingAvatar(url: avatarUrl, unread: true, radius: 30), const SizedBox(width: 18), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))), const Text('Yesterday', style: TextStyle(color: _green, fontWeight: FontWeight.w700))]), const SizedBox(height: 5), Text(_preview(status), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 16))])), const SizedBox(width: 8), const Icon(Icons.chevron_right, color: Colors.white54)])));
  String _preview(Map<String, dynamic> s) => s['type'] == 'text' ? (s['text'] ?? '').toString() : s['type'] == 'video' ? '▣ Video update' : '▧ Photo update';
}

class _RingAvatar extends StatelessWidget {
  final String url; final bool unread; final double radius;
  const _RingAvatar({required this.url, required this.unread, required this.radius});
  @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(3), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: unread ? _green : Colors.white24, width: 3)), child: CircleAvatar(radius: radius, backgroundColor: const Color(0xff20282c), backgroundImage: url.isNotEmpty ? NetworkImage(url) : null, child: url.isEmpty ? const Icon(Icons.person, color: Colors.white70) : null));
}

class _Thumb extends StatelessWidget {
  final Map<String, dynamic> status; const _Thumb({required this.status});
  @override Widget build(BuildContext context) { final t = status['type']; if (t == 'image' && (status['media_url'] ?? '').toString().isNotEmpty) return Image.network(status['media_url'], fit: BoxFit.cover, errorBuilder: (_, __, ___) => _text()); if (t == 'video') return const ColoredBox(color: Colors.black, child: Center(child: Icon(Icons.play_circle_outline, size: 56, color: Colors.white))); return _text(); }
  Widget _text() => Container(color: Color(int.tryParse((status['background'] ?? '2563eb').toString()) ?? 0xff2563eb), alignment: Alignment.center, padding: const EdgeInsets.all(16), child: Text((status['text'] ?? 'GG Status').toString(), maxLines: 7, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)));
}

class _StatusViewer extends StatefulWidget {
  final Map<String, dynamic> status, profile; final SupabaseClient sb;
  const _StatusViewer({required this.status, required this.profile, required this.sb});
  @override State<_StatusViewer> createState() => _StatusViewerState();
}

class _StatusViewerState extends State<_StatusViewer> {
  final reply = TextEditingController(); String reaction = '';
  String get displayName => (widget.profile['display_name']?.toString().trim().isNotEmpty == true) ? widget.profile['display_name'].toString() : 'GG User';
  String get avatarUrl => widget.profile['avatar_url']?.toString() ?? '';
  @override void dispose() { reply.dispose(); super.dispose(); }

  Future<void> react(String e) async { final me = widget.sb.auth.currentUser?.id; if (me == null) return; try { await widget.sb.from('status_reactions').upsert({'status_id': widget.status['id'], 'user_id': me, 'reaction': e}); setState(() => reaction = e); } catch (_) {} }
  Future<void> sendReply() async { final me = widget.sb.auth.currentUser?.id; final text = reply.text.trim(); if (me == null || text.isEmpty) return; try { await widget.sb.from('status_replies').insert({'status_id': widget.status['id'], 'user_id': me, 'body': text}); reply.clear(); if (mounted) _snack('Reply sent'); } catch (e) { _snack('Reply failed: $e'); } }
  void _snack(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  @override Widget build(BuildContext context) => Scaffold(backgroundColor: Colors.black, body: SafeArea(child: Stack(children: [
    Column(children: [Padding(padding: const EdgeInsets.fromLTRB(8, 4, 8, 0), child: Row(children: List.generate(5, (i) => Expanded(child: Container(height: 3, margin: const EdgeInsets.symmetric(horizontal: 4), decoration: BoxDecoration(color: i == 0 ? Colors.white : Colors.white38, borderRadius: BorderRadius.circular(4)))))), const SizedBox(height: 12), Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: Row(children: [IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back, color: Colors.white, size: 34)), const SizedBox(width: 4), _RingAvatar(url: avatarUrl, unread: false, radius: 25), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(displayName, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)), const Text('16h  •  Reshared', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600))])), IconButton(onPressed: () {}, icon: const Icon(Icons.more_vert, color: Colors.white, size: 30))])), const Spacer(), SizedBox(height: 560, width: double.infinity, child: _ViewerMedia(status: widget.status)), const Spacer(), Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(widget.status['text']?.toString().isNotEmpty == true ? widget.status['text'].toString() : 'GG Status...', style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w800))), Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 10), child: Row(children: [Expanded(child: Container(height: 58, decoration: BoxDecoration(color: const Color(0xff20282c), borderRadius: BorderRadius.circular(30)), child: Row(children: [const SizedBox(width: 20), Expanded(child: TextField(controller: reply, style: const TextStyle(color: Colors.white, fontSize: 17), decoration: const InputDecoration(hintText: 'Reply', hintStyle: TextStyle(color: Colors.white), border: InputBorder.none))), IconButton(onPressed: () => react('😍'), icon: const Text('😍', style: TextStyle(fontSize: 24))), IconButton(onPressed: () => react('😂'), icon: const Text('😂', style: TextStyle(fontSize: 24))), const SizedBox(width: 8)])), const SizedBox(width: 8), _RoundAction(icon: Icons.repeat, onTap: () {}), const SizedBox(width: 8), _RoundAction(icon: reaction.isNotEmpty ? Icons.favorite : Icons.favorite_border, onTap: () => react('❤️'))]))]))
  ]));
}

class _ViewerMedia extends StatelessWidget {
  final Map<String, dynamic> status; const _ViewerMedia({required this.status});
  @override Widget build(BuildContext context) { final t = status['type']; if (t == 'image' && (status['media_url'] ?? '').toString().isNotEmpty) return Image.network(status['media_url'], fit: BoxFit.contain, width: double.infinity, errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image, color: Colors.white, size: 48))); if (t == 'video') return const Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 82)); return Container(alignment: Alignment.center, padding: const EdgeInsets.all(30), color: Color(int.tryParse((status['background'] ?? '2563eb').toString()) ?? 0xff2563eb), child: Text((status['text'] ?? 'GG Status').toString(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900))); }
}

class _RoundAction extends StatelessWidget { final IconData icon; final VoidCallback onTap; const _RoundAction({required this.icon, required this.onTap}); @override Widget build(BuildContext context) => Material(color: const Color(0xff20282c), shape: const CircleBorder(), child: InkWell(onTap: onTap, customBorder: const CircleBorder(), child: SizedBox(width: 60, height: 60, child: Icon(icon, color: Colors.white, size: 30)))); }
