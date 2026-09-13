import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';
import 'offline_store.dart';

const _bg = Color(0xff0b1014);
const _green = Color(0xff25d366);

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

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final me = sb.auth.currentUser?.id;
    if (me != null) {
      try {
        final cached = await OfflineStore.loadData(me, 'statuses');
        final cachedProfiles = await OfflineStore.loadData(me, 'status_profiles');
        final cachedViewed = await OfflineStore.loadData(me, 'status_viewed');
        if (cached is List) statuses = cached.map((x) => Map<String, dynamic>.from(x as Map)).toList();
        if (cachedProfiles is Map) profiles = cachedProfiles.map((k, v) => MapEntry(k.toString(), Map<String, dynamic>.from(v as Map)));
        if (cachedViewed is List) viewed = cachedViewed.map((x) => '$x').toSet();
      } catch (_) {}
    }
    if (mounted) setState(() => loading = false);
    try {
      final rows = await sb.from('statuses').select('id,user_id,type,text,media_url,background,created_at,expires_at').gt('expires_at', DateTime.now().toUtc().toIso8601String()).order('created_at', ascending: false);
      statuses = List<Map<String, dynamic>>.from(rows);
      final ids = statuses.map((x) => '${x['user_id']}').toSet().toList();
      if (ids.isNotEmpty) {
        final rowsProfiles = await sb.from('profiles').select('id,display_name,username,avatar_url').inFilter('id', ids);
        profiles = {for (final p in List<Map<String, dynamic>>.from(rowsProfiles)) '${p['id']}': p};
      }
      if (me != null) {
        final rowsViewed = await sb.from('status_views').select('status_id').eq('viewer_id', me);
        viewed = {for (final x in List<Map<String, dynamic>>.from(rowsViewed)) '${x['status_id']}'};
        await OfflineStore.saveData(me, 'statuses', statuses);
        await OfflineStore.saveData(me, 'status_profiles', profiles);
        await OfflineStore.saveData(me, 'status_viewed', viewed.toList());
      }
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  String name(String id) {
    final value = profiles[id]?['display_name']?.toString().trim();
    return value != null && value.isNotEmpty ? value : 'GG User';
  }

  String avatar(String id) => profiles[id]?['avatar_url']?.toString() ?? '';

  Future<void> textStatus() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('My status'),
        content: TextField(controller: controller, autofocus: true, maxLines: 5, decoration: const InputDecoration(hintText: 'Type a status')),
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
      if (user == null) return;
      await sb.from('statuses').insert({'user_id': user.id, 'type': 'text', 'text': text, 'background': '075e54'});
      await load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not post: $e')));
    }
  }

  Future<void> mediaStatus(bool video) async {
    final file = video
        ? await picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 1))
        : await picker.pickImage(source: ImageSource.gallery, imageQuality: 90, maxWidth: 1800);
    if (file == null) return;
    if (mounted) setState(() => posting = true);
    try {
      final user = sb.auth.currentUser;
      if (user == null) return;
      final extension = file.path.contains('.') ? file.path.split('.').last.toLowerCase() : (video ? 'mp4' : 'jpg');
      final path = '${user.id}/${DateTime.now().microsecondsSinceEpoch}.$extension';
      await sb.storage.from('status-media').uploadBinary(path, await file.readAsBytes(), fileOptions: FileOptions(upsert: false, contentType: video ? 'video/mp4' : 'image/jpeg'));
      final url = await sb.storage.from('status-media').createSignedUrl(path, 86400);
      await sb.from('statuses').insert({'user_id': user.id, 'type': video ? 'video' : 'image', 'media_url': url});
      await load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    } finally {
      if (mounted) setState(() => posting = false);
    }
  }

  Future<void> openStatus(Map<String, dynamic> status) async {
    final me = sb.auth.currentUser?.id;
    final owner = '${status['user_id']}';
    if (me != null && owner != me) {
      try {
        await sb.from('status_views').upsert({'status_id': status['id'], 'viewer_id': me});
        viewed.add('${status['id']}');
        await OfflineStore.saveData(me, 'status_viewed', viewed.toList());
      } catch (_) {}
    }
    if (!mounted) return;
    final list = statuses.where((x) => '${x['user_id']}' == owner).toList();
    final index = list.indexWhere((x) => '${x['id']}' == '${status['id']}');
    await Navigator.push(context, MaterialPageRoute(builder: (_) => _StatusViewer(statuses: list, index: index < 0 ? 0 : index, name: name(owner), avatar: avatar(owner), onViewed: (item) async {
      if (me != null) {
        try { await sb.from('status_views').upsert({'status_id': item['id'], 'viewer_id': me}); } catch (_) {}
      }
    })));
    await load();
  }

  void create() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            const Padding(padding: EdgeInsets.all(20), child: Text('Create status', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
            ListTile(leading: const Icon(Icons.text_fields), title: const Text('Text status'), onTap: () { Navigator.pop(context); textStatus(); }),
            ListTile(leading: const Icon(Icons.photo_library), title: const Text('Photo'), onTap: () { Navigator.pop(context); mediaStatus(false); }),
            ListTile(leading: const Icon(Icons.videocam), title: const Text('Video'), onTap: () { Navigator.pop(context); mediaStatus(true); }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = sb.auth.currentUser?.id;
    final mine = statuses.where((x) => '${x['user_id']}' == me).toList();
    final byUser = <String, Map<String, dynamic>>{};
    for (final status in statuses) {
      final id = '${status['user_id']}';
      if (id != me) byUser.putIfAbsent(id, () => status);
    }
    final updates = byUser.values.toList();
    return Theme(
      data: ThemeData.dark(useMaterial3: true).copyWith(scaffoldBackgroundColor: _bg, colorScheme: ColorScheme.fromSeed(seedColor: _green, brightness: Brightness.dark)),
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          title: const Text('Updates', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
          actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh_rounded)), PopupMenuButton(itemBuilder: (_) => const [PopupMenuItem(child: Text('Status privacy')), PopupMenuItem(child: Text('Muted updates'))])],
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                physics: const ClampingScrollPhysics(),
                children: [
                  const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 6), child: Text('Status', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white70))),
                  _MyRow(mine: mine, avatar: me == null ? '' : avatar(me), onText: textStatus, onPhoto: () => mediaStatus(false), onOpen: mine.isEmpty ? null : () => openStatus(mine.first)),
                  if (updates.isNotEmpty) const Padding(padding: EdgeInsets.fromLTRB(16, 22, 16, 6), child: Text('Recent updates', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white70))),
                  ...updates.map((status) => _StatusRow(s: status, name: name('${status['user_id']}'), avatar: avatar('${status['user_id']}'), unread: !viewed.contains('${status['id']}'), onTap: () => openStatus(status))),
                  if (updates.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No recent updates'))),
                ],
              ),
        bottomNavigationBar: NavigationBar(
          backgroundColor: const Color(0xff090d11),
          selectedIndex: tab,
          onDestinationSelected: (index) {
            if (index == 0) { Navigator.pop(context); return; }
            setState(() => tab = index);
          },
          destinations: const [
            NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'Chats'),
            NavigationDestination(icon: Icon(Icons.circle_outlined), selectedIcon: Icon(Icons.circle, color: _green), label: 'Updates'),
            NavigationDestination(icon: Icon(Icons.groups_outlined), label: 'Communities'),
            NavigationDestination(icon: Icon(Icons.call_outlined), label: 'Calls'),
          ],
        ),
        floatingActionButton: posting
            ? const FloatingActionButton(onPressed: null, child: CircularProgressIndicator())
            : FloatingActionButton(backgroundColor: _green, foregroundColor: Colors.black, onPressed: create, child: const Icon(Icons.camera_alt_rounded)),
      ),
    );
  }
}

class _MyRow extends StatelessWidget {
  final List<Map<String, dynamic>> mine;
  final String avatar;
  final VoidCallback onText, onPhoto;
  final VoidCallback? onOpen;
  const _MyRow({required this.mine, required this.avatar, required this.onText, required this.onPhoto, required this.onOpen});
  @override Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
    leading: GestureDetector(onTap: onOpen, child: _Ring(url: avatar, unread: false)),
    title: const Text('My status', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
    subtitle: Text(mine.isEmpty ? 'Tap to add status update' : 'Tap to view your status', style: const TextStyle(color: Colors.white60)),
    trailing: Row(mainAxisSize: MainAxisSize.min, children: [IconButton(onPressed: onText, icon: const Icon(Icons.edit_rounded)), IconButton(onPressed: onPhoto, icon: const Icon(Icons.camera_alt_rounded))]),
  );
}

class _StatusRow extends StatelessWidget {
  final Map<String, dynamic> s;
  final String name, avatar;
  final bool unread;
  final VoidCallback onTap;
  const _StatusRow({required this.s, required this.name, required this.avatar, required this.unread, required this.onTap});
  @override Widget build(BuildContext context) => ListTile(onTap: onTap, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3), leading: _Ring(url: avatar, unread: unread), title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)), subtitle: Text(_time(s['created_at']), style: const TextStyle(color: Colors.white60)));
  String _time(dynamic value) { final date = DateTime.tryParse('$value')?.toLocal(); if (date == null) return 'Recently'; final age = DateTime.now().difference(date); if (age.inMinutes < 1) return 'Just now'; if (age.inHours < 1) return '${age.inMinutes}m ago'; if (age.inDays < 1) return '${age.inHours}h ago'; return '${age.inDays}d ago'; }
}

class _Ring extends StatelessWidget {
  final String url;
  final bool unread;
  const _Ring({required this.url, required this.unread});
  @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(2.5), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: unread ? _green : Colors.white30, width: unread ? 2.5 : 1.5)), child: CircleAvatar(radius: 25, backgroundImage: url.isNotEmpty ? NetworkImage(url) : null, child: url.isEmpty ? const Icon(Icons.person) : null));
}

class _StatusViewer extends StatefulWidget {
  final List<Map<String, dynamic>> statuses;
  final int index;
  final String name, avatar;
  final Future<void> Function(Map<String, dynamic>) onViewed;
  const _StatusViewer({required this.statuses, required this.index, required this.name, required this.avatar, required this.onViewed});
  @override State<_StatusViewer> createState() => _StatusViewerState();
}

class _StatusViewerState extends State<_StatusViewer> {
  late int i;
  Timer? timer;
  double progress = 0;
  VideoPlayerController? video;
  int generation = 0;

  @override
  void initState() { super.initState(); i = widget.index.clamp(0, widget.statuses.length - 1).toInt(); start(); }
  @override
  void dispose() { timer?.cancel(); video?.dispose(); super.dispose(); }

  Future<void> start() async {
    final currentGeneration = ++generation;
    timer?.cancel();
    await video?.dispose();
    video = null;
    progress = 0;
    final status = widget.statuses[i];
    await widget.onViewed(status);
    final type = '${status['type']}';
    final url = status['media_url']?.toString() ?? '';
    if (type == 'video' && url.isNotEmpty) {
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      video = controller;
      try {
        await controller.initialize();
        if (!mounted || currentGeneration != generation) return;
        setState(() {});
        await controller.play();
        controller.addListener(() => _videoProgress(controller, currentGeneration));
      } catch (_) { if (mounted) setState(() {}); }
    } else {
      timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (!mounted) return;
        setState(() => progress += .02);
        if (progress >= 1) next();
      });
    }
    if (mounted) setState(() {});
  }

  void _videoProgress(VideoPlayerController controller, int currentGeneration) {
    if (!mounted || currentGeneration != generation || !controller.value.isInitialized) return;
    final duration = controller.value.duration.inMilliseconds;
    if (duration > 0) setState(() => progress = (controller.value.position.inMilliseconds / duration).clamp(0, 1).toDouble());
    if (controller.value.position >= controller.value.duration && duration > 0) next();
  }

  void next() { timer?.cancel(); if (i < widget.statuses.length - 1) { setState(() => i++); start(); } else if (mounted) Navigator.pop(context); }
  void prev() { timer?.cancel(); if (i > 0) { setState(() => i--); start(); } else { start(); } }
  void pause() { timer?.cancel(); video?.pause(); }
  void resume() { if (video != null) { video!.play(); } else { timer = Timer.periodic(const Duration(milliseconds: 100), (_) { if (!mounted) return; setState(() => progress += .02); if (progress >= 1) next(); }); } }

  @override
  Widget build(BuildContext context) {
    final status = widget.statuses[i];
    final type = '${status['type']}';
    final url = status['media_url']?.toString() ?? '';
    final bg = Color(int.tryParse('0xff${status['background'] ?? '075e54'}') ?? 0xff075e54);
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapUp: (details) => details.localPosition.dx < MediaQuery.of(context).size.width / 2 ? prev() : next(),
        onLongPress: pause,
        onLongPressUp: resume,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (type == 'image' && url.isNotEmpty)
              Image.network(url, fit: BoxFit.contain, errorBuilder: (_, __, ___) => ColoredBox(color: bg))
            else if (type == 'text')
              Container(color: bg, alignment: Alignment.center, padding: const EdgeInsets.all(34), child: Text(status['text']?.toString() ?? '', textAlign: TextAlign.center, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Colors.white)))
            else if (type == 'video' && video?.value.isInitialized == true)
              Center(child: AspectRatio(aspectRatio: video!.value.aspectRatio, child: VideoPlayer(video!)))
            else
              const Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 72)),
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 10,
              right: 10,
              child: Row(children: [for (int n = 0; n < widget.statuses.length; n++) Expanded(child: Container(height: 3, margin: const EdgeInsets.symmetric(horizontal: 2), decoration: BoxDecoration(color: n < i ? Colors.white : n == i ? Colors.white38 : Colors.white24, borderRadius: BorderRadius.circular(3)), child: n == i ? Align(alignment: Alignment.centerLeft, child: FractionallySizedBox(widthFactor: progress.clamp(0, 1).toDouble(), child: Container(color: Colors.white))) : null))]),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 20,
              left: 16,
              right: 8,
              child: Row(children: [CircleAvatar(radius: 19, backgroundImage: widget.avatar.isNotEmpty ? NetworkImage(widget.avatar) : null, child: widget.avatar.isEmpty ? const Icon(Icons.person) : null), const SizedBox(width: 10), Expanded(child: Text(widget.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))), IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white))]),
            ),
          ],
        ),
      ),
    );
  }
}
