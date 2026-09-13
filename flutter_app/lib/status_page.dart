import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    if (mounted) {
      setState(() => loading = true);
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

      final me = sb.auth.currentUser?.id;
      if (me != null) {
        final rows = await sb
            .from('status_views')
            .select('status_id')
            .eq('viewer_id', me);

        viewed = {
          for (final row in List<Map<String, dynamic>>.from(rows))
            row['status_id'].toString(),
        };
      }
    } catch (e) {
      if (mounted) {
        _snack('Could not load updates: $e');
      }
    }

    if (mounted) {
      setState(() => loading = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String displayName(String id) {
    final value = profiles[id]?['display_name']?.toString().trim();
    return value == null || value.isEmpty ? 'GG User' : value;
  }

  String avatarUrl(String id) {
    return profiles[id]?['avatar_url']?.toString() ?? '';
  }

  Future<void> createText() async {
    final controller = TextEditingController();

    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('New status'),
          content: TextField(
            controller: controller,
            maxLines: 5,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'What is happening?',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                controller.text.trim(),
              ),
              child: const Text('Post'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (text == null || text.isEmpty) return;

    try {
      final user = sb.auth.currentUser;
      if (user == null) {
        _snack('Please sign in first.');
        return;
      }

      await sb.from('statuses').insert(<String, dynamic>{
        'user_id': user.id,
        'type': 'text',
        'text': text,
        'background': '2563eb',
      });

      await load();
    } catch (e) {
      _snack('Could not post: $e');
    }
  }

  Future<void> pickMedia(bool video) async {
    final XFile? file = video
        ? await picker.pickVideo(
            source: ImageSource.gallery,
            maxDuration: const Duration(minutes: 1),
          )
        : await picker.pickImage(
            source: ImageSource.gallery,
            imageQuality: 88,
            maxWidth: 1600,
          );

    if (file == null) return;

    if (mounted) {
      setState(() => posting = true);
    }

    try {
      final user = sb.auth.currentUser;
      if (user == null) {
        _snack('Please sign in first.');
        return;
      }

      final extension = file.path.contains('.')
          ? file.path.split('.').last.toLowerCase()
          : (video ? 'mp4' : 'jpg');
      final path =
          '${user.id}/${DateTime.now().microsecondsSinceEpoch}.$extension';

      await sb.storage.from('status-media').uploadBinary(
            path,
            await file.readAsBytes(),
            fileOptions: FileOptions(
              upsert: false,
              contentType: video ? 'video/mp4' : 'image/jpeg',
            ),
          );

      final url = await sb.storage
          .from('status-media')
          .createSignedUrl(path, 86400);

      await sb.from('statuses').insert(<String, dynamic>{
        'user_id': user.id,
        'type': video ? 'video' : 'image',
        'media_url': url,
      });

      await load();
    } catch (e) {
      _snack('Upload failed: $e');
    } finally {
      if (mounted) {
        setState(() => posting = false);
      }
    }
  }

  Future<void> openStatus(Map<String, dynamic> status) async {
    final me = sb.auth.currentUser?.id;
    final owner = status['user_id']?.toString();

    if (me != null && owner != null && me != owner) {
      try {
        await sb.from('status_views').upsert(<String, dynamic>{
          'status_id': status['id'],
          'viewer_id': me,
        });
        viewed.add(status['id'].toString());
      } catch (_) {}
    }

    if (!mounted) return;

    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => _StatusViewer(
          status: status,
          profile: owner == null ? <String, dynamic>{} : profiles[owner] ?? {},
          sb: sb,
        ),
      ),
    );

    await load();
  }

  @override
  Widget build(BuildContext context) {
    final me = sb.auth.currentUser?.id;
    final mine = statuses.where((s) => s['user_id']?.toString() == me).toList();

    final grouped = <String, Map<String, dynamic>>{};
    for (final status in statuses) {
      final owner = status['user_id']?.toString();
      if (owner != null && owner != me) {
        grouped.putIfAbsent(owner, () => status);
      }
    }
    final updates = grouped.values.toList();

    return Theme(
      data: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: _bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _green,
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: _bg,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          title: const Text(
            'Updates',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          actions: <Widget>[
            IconButton(
              onPressed: load,
              icon: const Icon(Icons.refresh, size: 28),
            ),
            PopupMenuButton<String>(
              onSelected: (_) {},
              itemBuilder: (_) => const <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'settings',
                  child: Text('Updates settings'),
                ),
              ],
            ),
          ],
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                color: _green,
                onRefresh: load,
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 18),
                  children: <Widget>[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(30, 4, 24, 12),
                      child: Text(
                        'Status',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 260,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 30),
                        children: <Widget>[
                          _AddStatusCard(
                            onTap: createText,
                            onMediaTap: () => pickMedia(false),
                            image: mine.isNotEmpty
                                ? _mediaUrl(mine.first)
                                : null,
                          ),
                          ...updates.take(8).map(
                                (status) => _StatusCard(
                                  status: status,
                                  name: displayName(
                                    status['user_id'].toString(),
                                  ),
                                  avatarUrl: avatarUrl(
                                    status['user_id'].toString(),
                                  ),
                                  unread: !viewed.contains(
                                    status['id'].toString(),
                                  ),
                                  onTap: () => openStatus(status),
                                ),
                              ),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(30, 26, 24, 8),
                      child: Text(
                        'Channels',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 30),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          onPressed: () => _snack(
                            'Channel discovery coming soon',
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: _surface,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text(
                            'Explore',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (updates.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(
                          child: Text(
                            'No channel updates yet',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ...updates.take(10).map(
                          (status) => _ChannelRow(
                            status: status,
                            name: displayName(
                              status['user_id'].toString(),
                            ),
                            avatarUrl: avatarUrl(
                              status['user_id'].toString(),
                            ),
                            onTap: () => openStatus(status),
                          ),
                        ),
                  ],
                ),
              ),
        bottomNavigationBar: NavigationBar(
          backgroundColor: const Color(0xff090d11),
          indicatorColor: const Color(0xff073e2a),
          selectedIndex: tab,
          onDestinationSelected: (index) {
            if (index == 0) {
              Navigator.pop(context);
              return;
            }
            setState(() => tab = index);
            if (index == 2 || index == 3) {
              _snack(index == 2 ? 'Communities' : 'Calls');
            }
          },
          destinations: const <NavigationDestination>[
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline),
              selectedIcon: Icon(Icons.chat_bubble),
              label: 'Chats',
            ),
            NavigationDestination(
              icon: Icon(Icons.circle_outlined),
              selectedIcon: Icon(Icons.circle, color: _green),
              label: 'Updates',
            ),
            NavigationDestination(
              icon: Icon(Icons.groups_outlined),
              label: 'Communities',
            ),
            NavigationDestination(
              icon: Icon(Icons.call_outlined),
              label: 'Calls',
            ),
          ],
        ),
        floatingActionButton: posting
            ? const FloatingActionButton(
                onPressed: null,
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : FloatingActionButton(
                backgroundColor: _green,
                foregroundColor: Colors.black,
                onPressed: () => pickMedia(false),
                child: const Icon(Icons.camera_alt),
              ),
      ),
    );
  }

  String? _mediaUrl(Map<String, dynamic> status) {
    return status['type'] == 'image'
        ? status['media_url']?.toString()
        : null;
  }
}

class _AddStatusCard extends StatelessWidget {
  final VoidCallback onTap;
  final VoidCallback onMediaTap;
  final String? image;

  const _AddStatusCard({
    required this.onTap,
    required this.onMediaTap,
    this.image,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 145,
        margin: const EdgeInsets.only(right: 14),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white12),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(23),
              child: image != null && image!.isNotEmpty
                  ? Image.network(image!, fit: BoxFit.cover)
                  : const ColoredBox(color: Color(0xff172025)),
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: Container(
                height: 100,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[Colors.transparent, Colors.black87],
                  ),
                ),
              ),
            ),
            const Positioned(
              left: 16,
              bottom: 14,
              child: Text(
                'Add status',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            Positioned(
              left: 14,
              bottom: 62,
              child: GestureDetector(
                onTap: onMediaTap,
                child: const CircleAvatar(
                  backgroundColor: _green,
                  radius: 20,
                  child: Icon(Icons.add, color: Colors.black, size: 28),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final Map<String, dynamic> status;
  final String name;
  final String avatarUrl;
  final bool unread;
  final VoidCallback onTap;

  const _StatusCard({
    required this.status,
    required this.name,
    required this.avatarUrl,
    required this.unread,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 145,
        margin: const EdgeInsets.only(right: 14),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white12),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(23),
              child: _Thumb(status: status),
            ),
            Positioned(
              top: 10,
              left: 10,
              child: _RingAvatar(
                url: avatarUrl,
                unread: unread,
                radius: 28,
              ),
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: Container(
                height: 92,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[Colors.transparent, Colors.black87],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 14,
              bottom: 14,
              right: 8,
              child: Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  final Map<String, dynamic> status;
  final String name;
  final String avatarUrl;
  final VoidCallback onTap;

  const _ChannelRow({
    required this.status,
    required this.name,
    required this.avatarUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(30, 12, 30, 12),
        child: Row(
          children: <Widget>[
            _RingAvatar(url: avatarUrl, unread: true, radius: 30),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const Text(
                        'Recent',
                        style: TextStyle(
                          color: _green,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _preview(status),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Colors.white54),
          ],
        ),
      ),
    );
  }

  String _preview(Map<String, dynamic> status) {
    final type = status['type']?.toString();
    if (type == 'text') return (status['text'] ?? '').toString();
    if (type == 'video') return 'Video update';
    return 'Photo update';
  }
}

class _RingAvatar extends StatelessWidget {
  final String url;
  final bool unread;
  final double radius;

  const _RingAvatar({
    required this.url,
    required this.unread,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: unread ? _green : Colors.white24,
          width: 3,
        ),
      ),
      child: CircleAvatar(
        radius: radius,
        backgroundColor: const Color(0xff20282c),
        backgroundImage: url.isNotEmpty ? NetworkImage(url) : null,
        child: url.isEmpty
            ? const Icon(Icons.person, color: Colors.white70)
            : null,
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final Map<String, dynamic> status;

  const _Thumb({required this.status});

  @override
  Widget build(BuildContext context) {
    final type = status['type']?.toString();
    final media = status['media_url']?.toString() ?? '';

    if (type == 'image' && media.isNotEmpty) {
      return Image.network(
        media,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _text(),
      );
    }

    if (type == 'video') {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Icon(
            Icons.play_circle_outline,
            size: 56,
            color: Colors.white,
          ),
        ),
      );
    }

    return _text();
  }

  Widget _text() {
    return Container(
      color: _statusColor(status['background']),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      child: Text(
        (status['text'] ?? 'GG Status').toString(),
        maxLines: 7,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }

  Color _statusColor(dynamic value) {
    final raw = value?.toString() ?? '2563eb';
    final normalized = raw.startsWith('0x') ? raw : '0xff$raw';
    return Color(int.tryParse(normalized) ?? 0xff2563eb);
  }
}

class _StatusViewer extends StatefulWidget {
  final Map<String, dynamic> status;
  final Map<String, dynamic> profile;
  final SupabaseClient sb;

  const _StatusViewer({
    required this.status,
    required this.profile,
    required this.sb,
  });

  @override
  State<_StatusViewer> createState() => _StatusViewerState();
}

class _StatusViewerState extends State<_StatusViewer> {
  final TextEditingController reply = TextEditingController();
  String reaction = '';

  String get displayName {
    final value = widget.profile['display_name']?.toString().trim();
    return value == null || value.isEmpty ? 'GG User' : value;
  }

  String get avatarUrl => widget.profile['avatar_url']?.toString() ?? '';

  @override
  void dispose() {
    reply.dispose();
    super.dispose();
  }

  Future<void> react(String emoji) async {
    final me = widget.sb.auth.currentUser?.id;
    if (me == null) return;

    try {
      await widget.sb.from('status_reactions').upsert(<String, dynamic>{
        'status_id': widget.status['id'],
        'user_id': me,
        'reaction': emoji,
      });
      if (mounted) {
        setState(() => reaction = emoji);
      }
    } catch (_) {}
  }

  Future<void> sendReply() async {
    final me = widget.sb.auth.currentUser?.id;
    final text = reply.text.trim();
    if (me == null || text.isEmpty) return;

    try {
      await widget.sb.from('status_replies').insert(<String, dynamic>{
        'status_id': widget.status['id'],
        'user_id': me,
        'body': text,
      });
      reply.clear();
      _snack('Reply sent');
    } catch (e) {
      _snack('Reply failed: $e');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.status['text']?.toString() ?? '';

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                children: List<Widget>.generate(
                  5,
                  (index) => Expanded(
                    child: Container(
                      height: 3,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: index == 0 ? Colors.white : Colors.white38,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: <Widget>[
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                  const SizedBox(width: 4),
                  _RingAvatar(url: avatarUrl, unread: false, radius: 25),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(
                      Icons.more_vert,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: SizedBox(
                  width: double.infinity,
                  child: _ViewerMedia(status: widget.status),
                ),
              ),
            ),
            if (text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Container(
                      height: 58,
                      decoration: BoxDecoration(
                        color: const Color(0xff20282c),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Row(
                        children: <Widget>[
                          const SizedBox(width: 20),
                          Expanded(
                            child: TextField(
                              controller: reply,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                              ),
                              decoration: const InputDecoration(
                                hintText: 'Reply',
                                hintStyle: TextStyle(color: Colors.white70),
                                border: InputBorder.none,
                              ),
                              onSubmitted: (_) => sendReply(),
                            ),
                          ),
                          IconButton(
                            onPressed: () => react('😍'),
                            icon: const Text(
                              '😍',
                              style: TextStyle(fontSize: 24),
                            ),
                          ),
                          IconButton(
                            onPressed: () => react('😂'),
                            icon: const Text(
                              '😂',
                              style: TextStyle(fontSize: 24),
                            ),
                          ),
                          IconButton(
                            onPressed: sendReply,
                            icon: const Icon(
                              Icons.send,
                              color: _green,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _RoundAction(icon: Icons.repeat, onTap: () {}),
                  const SizedBox(width: 8),
                  _RoundAction(
                    icon: reaction.isNotEmpty
                        ? Icons.favorite
                        : Icons.favorite_border,
                    onTap: () => react('❤️'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewerMedia extends StatelessWidget {
  final Map<String, dynamic> status;

  const _ViewerMedia({required this.status});

  @override
  Widget build(BuildContext context) {
    final type = status['type']?.toString();
    final media = status['media_url']?.toString() ?? '';

    if (type == 'image' && media.isNotEmpty) {
      return Image.network(
        media,
        fit: BoxFit.contain,
        width: double.infinity,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(
            Icons.broken_image,
            color: Colors.white,
            size: 48,
          ),
        ),
      );
    }

    if (type == 'video') {
      return const Center(
        child: Icon(
          Icons.play_circle_fill,
          color: Colors.white,
          size: 82,
        ),
      );
    }

    final background = status['background']?.toString() ?? '2563eb';
    final color = Color(
      int.tryParse(
            background.startsWith('0x') ? background : '0xff$background',
          ) ??
          0xff2563eb,
    );

    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(30),
      color: color,
      child: Text(
        (status['text'] ?? 'GG Status').toString(),
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 34,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _RoundAction({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xff20282c),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 60,
          height: 60,
          child: Icon(icon, color: Colors.white, size: 30),
        ),
      ),
    );
  }
}
