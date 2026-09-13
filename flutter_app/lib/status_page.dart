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
        if (cached is List) {
          statuses = cached.map((x) => Map<String, dynamic>.from(x as Map)).toList();
        }
        if (cachedProfiles is Map) {
          profiles = cachedProfiles.map(
            (k, v) => MapEntry('$k', Map<String, dynamic>.from(v as Map)),
          );
        }
        if (cachedViewed is List) viewed = cachedViewed.map((x) => '$x').toSet();
      } catch (_) {}
    }
    if (mounted) setState(() => loading = false);

    try {
      final rows = await sb
          .from('statuses')
          .select('id,user_id,type,text,media_url,background,created_at,expires_at')
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .order('created_at', ascending: false);
      statuses = List<Map<String, dynamic>>.from(rows);
      final ids = statuses.map((x) => '${x['user_id']}').toSet().toList();
      if (ids.isNotEmpty) {
        final ps = await sb.from('profiles').select('id,display_name,username,avatar_url').inFilter('id', ids);
        profiles = {
          for (final p in List<Map<String, dynamic>>.from(ps)) '${p['id']}': p,
        };
      }
      if (me != null) {
        final rv = await sb.from('status_views').select('status_id').eq('viewer_id', me);
        viewed = {for (final x in List<Map<String, dynamic>>.from(rv)) '${x['status_id']}'};
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
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
          decoration: const InputDecoration(hintText: 'Type a status'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Post'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.isEmpty) return;
    try {
      final user = sb.auth.currentUser;
      if (user == null) return;
      await sb.from('statuses').insert({
        'user_id': user.id,
        'type': 'text',
        'text': text,
        'background': '075e54',
      });
      await load();
    } catch (e) {
      if (mounted) snack('Could not post: $e');
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
      final ext = file.path.contains('.')
          ? file.path.split('.').last.toLowerCase()
          : (video ? 'mp4' : 'jpg');
      final path = '${user.id}/${DateTime.now().microsecondsSinceEpoch}.$ext';
      await sb.storage.from('status-media').uploadBinary(
        path,
        await file.readAsBytes(),
        fileOptions: FileOptions(
          upsert: false,
          contentType: video ? 'video/mp4' : 'image/jpeg',
        ),
      );
      final url = await sb.storage.from('status-media').createSignedUrl(path, 86400);
      await sb.from('statuses').insert({
        'user_id': user.id,
        'type': video ? 'video' : 'image',
        'media_url': url,
      });
      await load();
    } catch (e) {
      if (mounted) snack('Upload failed: $e');
    } finally {
      if (mounted) setState(() => posting = false);
    }
  }

  void snack(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> openStatus(Map<String, dynamic> status) async {
    final me = sb.auth.currentUser?.id;
    final owner = '${status['user_id']}';
    final list = statuses.where((x) => '${x['user_id']}' == owner).toList();
    final index = list.indexWhere((x) => '${x['id']}' == '${status['id']}');
    if (list.isEmpty) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _StatusViewer(
          statuses: list,
          index: index < 0 ? 0 : index,
          name: name(owner),
          avatar: avatar(owner),
          onViewed: (item) async {
            if (me == null || owner == me) return;
            try {
              await sb.from('status_views').upsert({'status_id': item['id'], 'viewer_id': me});
              viewed.add('${item['id']}');
              await OfflineStore.saveData(me, 'status_viewed', viewed.toList());
            } catch (_) {}
          },
        ),
      ),
    );
    await load();
  }

  void create() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Create status', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ),
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: const Text('Text status'),
              onTap: () { Navigator.pop(sheetContext); textStatus(); },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Photo'),
              onTap: () { Navigator.pop(sheetContext); mediaStatus(false); },
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('Video'),
              onTap: () { Navigator.pop(sheetContext); mediaStatus(true); },
            ),
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
      data: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: _bg,
        colorScheme: ColorScheme.fromSeed(seedColor: _green, brightness: Brightness.dark),
      ),
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          title: const Text('Status', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          actions: [
            IconButton(onPressed: load, icon: const Icon(Icons.refresh_rounded)),
            PopupMenuButton<String>(
              onSelected: (_) {},
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'privacy', child: Text('Status privacy')),
                PopupMenuItem(value: 'muted', child: Text('Muted updates')),
              ],
            ),
          ],
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.only(top: 12, bottom: 24),
                children: [
                  SizedBox(
                    height: 575,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      itemCount: updates.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (_, index) {
                        if (index == 0) {
                          return _StatusCard(
                            mine: true,
                            name: 'Add status',
                            status: mine.isEmpty ? null : mine.first,
                            avatar: me == null ? '' : avatar(me),
                            onTap: mine.isEmpty ? create : () => openStatus(mine.first),
                            onAdd: create,
                          );
                        }
                        final status = updates[index - 1];
                        return _StatusCard(
                          mine: false,
                          name: name('${status['user_id']}'),
                          status: status,
                          avatar: avatar('${status['user_id']}'),
                          unread: !viewed.contains('${status['id']}'),
                          onTap: () => openStatus(status),
                          onAdd: null,
                        );
                      },
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 18, 16, 8),
                    child: Text('Recent updates', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                  ...updates.map(
                    (status) => ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                      leading: _Ring(url: avatar('${status['user_id']}'), unread: !viewed.contains('${status['id']}')),
                      title: Text(name('${status['user_id']}'), style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(_time(status['created_at']), style: const TextStyle(color: Colors.white60)),
                      onTap: () => openStatus(status),
                    ),
                  ),
                  if (updates.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('No recent updates')),
                    ),
                ],
              ),
        bottomNavigationBar: NavigationBar(
          backgroundColor: const Color(0xff090d11),
          selectedIndex: tab,
          onDestinationSelected: (index) {
            if (index == 0) {
              Navigator.pop(context);
            } else {
              setState(() => tab = index);
            }
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
            : FloatingActionButton(
                backgroundColor: _green,
                foregroundColor: Colors.black,
                onPressed: create,
                child: const Icon(Icons.camera_alt_rounded),
              ),
      ),
    );
  }

  String _time(dynamic value) {
    final date = DateTime.tryParse('$value')?.toLocal();
    if (date == null) return 'Recently';
    final age = DateTime.now().difference(date);
    if (age.inMinutes < 1) return 'Just now';
    if (age.inHours < 1) return '${age.inMinutes}m ago';
    if (age.inDays < 1) return '${age.inHours}h ago';
    return '${age.inDays}d ago';
  }
}

class _StatusCard extends StatelessWidget {
  final bool mine;
  final String name;
  final Map<String, dynamic>? status;
  final String avatar;
  final bool unread;
  final VoidCallback onTap;
  final VoidCallback? onAdd;

  const _StatusCard({
    required this.mine,
    required this.name,
    required this.status,
    required this.avatar,
    required this.onTap,
    required this.onAdd,
    this.unread = false,
  });

  @override
  Widget build(BuildContext context) {
    final url = status?['media_url']?.toString() ?? '';
    final type = status?['type']?.toString() ?? '';
    Widget content;
    if (type == 'image' && url.isNotEmpty) {
      content = Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: const Color(0xff182126)));
    } else if (type == 'text') {
      content = Container(
        color: const Color(0xff075e54),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(18),
        child: Text(status?['text']?.toString() ?? '', textAlign: TextAlign.center, maxLines: 8, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      );
    } else {
      content = Container(
        color: const Color(0xff10161a),
        alignment: Alignment.center,
        child: Icon(type == 'video' ? Icons.play_circle_fill : Icons.add_circle, color: Colors.white, size: 52),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 205,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), color: const Color(0xff151b20), border: Border.all(color: Colors.white12)),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            content,
            if (!mine)
              Positioned(
                top: 14,
                left: 14,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(shape: BoxShape.circle, color: unread ? _green : Colors.white70),
                  child: CircleAvatar(radius: 23, backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null, child: avatar.isEmpty ? const Icon(Icons.person) : null),
                ),
              ),
            if (mine && onAdd != null)
              Positioned(
                top: 14,
                left: 14,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: _green, border: Border.all(color: Colors.black, width: 3)),
                  child: const Icon(Icons.add, color: Colors.black, size: 32),
                ),
              ),
            Positioned(
              left: 16,
              right: 12,
              bottom: 16,
              child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800, shadows: [Shadow(blurRadius: 8, color: Colors.black)])),
            ),
          ],
        ),
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  final String url;
  final bool unread;
  const _Ring({required this.url, required this.unread});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: unread ? _green : Colors.white30, width: unread ? 2.5 : 1.5)),
      child: CircleAvatar(radius: 25, backgroundImage: url.isNotEmpty ? NetworkImage(url) : null, child: url.isEmpty ? const Icon(Icons.person) : null),
    );
  }
}

class _StatusViewer extends StatefulWidget {
  final List<Map<String, dynamic>> statuses;
  final int index;
  final String name;
  final String avatar;
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
  bool paused = false;

  @override
  void initState() {
    super.initState();
    i = widget.index.clamp(0, widget.statuses.length - 1).toInt();
    start();
  }

  @override
  void dispose() {
    timer?.cancel();
    video?.dispose();
    super.dispose();
  }

  Future<void> start() async {
    final currentGeneration = ++generation;
    timer?.cancel();
    await video?.dispose();
    video = null;
    progress = 0;
    paused = false;

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
        controller.addListener(() => videoProgress(controller, currentGeneration));
      } catch (_) {}
    } else {
      timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (!mounted || paused) return;
        setState(() => progress += 0.02);
        if (progress >= 1) next();
      });
    }
    if (mounted) setState(() {});
  }

  void videoProgress(VideoPlayerController controller, int currentGeneration) {
    if (!mounted || currentGeneration != generation || !controller.value.isInitialized) return;
    final duration = controller.value.duration.inMilliseconds;
    if (duration > 0) {
      final value = controller.value.position.inMilliseconds / duration;
      setState(() => progress = value.clamp(0, 1).toDouble());
      if (controller.value.position >= controller.value.duration) next();
    }
  }

  void next() {
    timer?.cancel();
    if (i < widget.statuses.length - 1) {
      setState(() => i++);
      start();
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  void prev() {
    timer?.cancel();
    if (i > 0) {
      setState(() => i--);
      start();
    } else {
      start();
    }
  }

  void pause() {
    paused = true;
    timer?.cancel();
    video?.pause();
    setState(() {});
  }

  void resume() {
    paused = false;
    video?.play();
    if (video == null) {
      timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (!mounted || paused) return;
        setState(() => progress += 0.02);
        if (progress >= 1) next();
      });
    }
    setState(() {});
  }

  void react(String emoji) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reaction $emoji sent')));
  }

  Future<void> reply() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reply to status'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: 'Message')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Send')),
        ],
      ),
    );
    controller.dispose();
    if (text != null && text.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reply sent')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.statuses[i];
    final type = '${status['type']}';
    final url = status['media_url']?.toString() ?? '';
    final bgValue = int.tryParse('0xff${status['background'] ?? '075e54'}') ?? 0xff075e54;
    final bg = Color(bgValue);
    final top = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;

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
              top: top + 8,
              left: 8,
              right: 8,
              child: Row(
                children: List.generate(widget.statuses.length, (n) {
                  Widget? fill;
                  if (n < i) {
                    fill = Container(color: Colors.white);
                  } else if (n == i) {
                    fill = Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: progress.clamp(0, 1).toDouble(),
                        child: Container(color: Colors.white),
                      ),
                    );
                  }
                  return Expanded(
                    child: Container(
                      height: 3,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
                      child: fill,
                    ),
                  );
                }),
              ),
            ),
            Positioned(
              top: top + 18,
              left: 14,
              right: 8,
              child: Row(
                children: [
                  CircleAvatar(radius: 20, backgroundImage: widget.avatar.isNotEmpty ? NetworkImage(widget.avatar) : null, child: widget.avatar.isEmpty ? const Icon(Icons.person) : null),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        SizedBox.shrink(),
                      ],
                    ),
                  ),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.more_vert, color: Colors.white, size: 30)),
                ],
              ),
            ),
            Positioned(
              top: top + 54,
              left: 84,
              right: 60,
              child: Text(widget.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            if (paused) const Center(child: Icon(Icons.pause_circle_filled, color: Colors.white70, size: 58)),
            Positioned(
              bottom: bottom + 18,
              left: 14,
              right: 14,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 58,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      decoration: BoxDecoration(color: const Color(0xff20282d), borderRadius: BorderRadius.circular(30)),
                      child: Row(
                        children: [
                          Expanded(child: GestureDetector(onTap: reply, child: const Text('Reply', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)))),
                          GestureDetector(onTap: () => react('😍'), child: const Text('😍', style: TextStyle(fontSize: 25))),
                          const SizedBox(width: 18),
                          GestureDetector(onTap: () => react('😂'), child: const Text('😂', style: TextStyle(fontSize: 25))),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _ViewerButton(icon: Icons.repeat_rounded, onTap: () => snack('Status reshared')),
                  const SizedBox(width: 10),
                  _ViewerButton(icon: Icons.favorite_border_rounded, onTap: () => react('❤️')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewerButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ViewerButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xff20282d),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(width: 58, height: 58, child: Icon(Icons.repeat_rounded, color: Colors.white, size: 29)),
      ),
    );
  }
}
