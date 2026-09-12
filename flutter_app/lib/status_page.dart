import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  List<Map<String, dynamic>> statuses = [];
  Map<String, Map<String, dynamic>> profiles = {};
  Set<String> viewed = {};

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (mounted) setState(() => loading = true);
    try {
      final rows = await sb
          .from('statuses')
          .select('id,user_id,type,text,media_url,background,created_at,expires_at')
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .order('created_at', ascending: false);
      final list = List<Map<String, dynamic>>.from(rows);
      final ids = list.map((e) => e['user_id'].toString()).toSet().toList();
      if (ids.isNotEmpty) {
        final ps = await sb.from('profiles').select('id,display_name,username,avatar_url').inFilter('id', ids);
        profiles = {for (final p in List<Map<String, dynamic>>.from(ps)) p['id'].toString(): p};
      }
      final me = sb.auth.currentUser?.id;
      if (me != null) {
        final v = await sb.from('status_views').select('status_id').eq('viewer_id', me);
        viewed = {for (final x in List<Map<String, dynamic>>.from(v)) x['status_id'].toString()};
      }
      if (mounted) setState(() => statuses = list);
    } catch (e) {
      if (mounted) _snack('Could not load statuses: $e');
    }
    if (mounted) setState(() => loading = false);
  }

  void _snack(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

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
    if (text != null && text.isNotEmpty) await _insert('text', text: text);
  }

  Future<void> pickMedia(bool video) async {
    final XFile? file = video
        ? await picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 1))
        : await picker.pickImage(source: ImageSource.gallery, imageQuality: 88, maxWidth: 1600);
    if (file == null) return;
    setState(() => posting = true);
    try {
      final uid = sb.auth.currentUser!.id;
      final extension = file.path.contains('.') ? file.path.split('.').last.toLowerCase() : (video ? 'mp4' : 'jpg');
      final path = '$uid/${DateTime.now().microsecondsSinceEpoch}.$extension';
      final bytes = await file.readAsBytes();
      await sb.storage.from('status-media').uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(upsert: false, contentType: video ? 'video/mp4' : 'image/jpeg'),
      );
      final url = await sb.storage.from('status-media').createSignedUrl(path, 86400);
      await _insert(video ? 'video' : 'image', mediaUrl: url);
    } catch (e) {
      _snack('Upload failed: $e');
    }
    if (mounted) setState(() => posting = false);
  }

  Future<void> _insert(String type, {String? text, String? mediaUrl}) async {
    try {
      await sb.from('statuses').insert({
        'user_id': sb.auth.currentUser!.id,
        'type': type,
        'text': text,
        'media_url': mediaUrl,
      });
      await load();
    } catch (e) {
      _snack('Could not post status: $e');
    }
  }

  Future<void> viewStatus(Map<String, dynamic> status) async {
    final me = sb.auth.currentUser?.id;
    if (me != null && me != status['user_id']) {
      try {
        await sb.from('status_views').upsert({'status_id': status['id'], 'viewer_id': me});
        viewed.add(status['id'].toString());
      } catch (_) {}
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => _Viewer(status: status, sb: sb, onChanged: load, isMine: status['user_id'] == me),
    );
  }

  Future<void> deleteStatus(Map<String, dynamic> status) async {
    try {
      await sb.from('statuses').delete().eq('id', status['id']);
      await load();
    } catch (e) {
      _snack('Delete failed: $e');
    }
  }

  String name(String id) {
    final profile = profiles[id];
    final display = profile?['display_name']?.toString().trim() ?? '';
    return display.isNotEmpty ? display : 'GG User';
  }

  @override
  Widget build(BuildContext context) {
    final me = sb.auth.currentUser?.id;
    final mine = statuses.where((s) => s['user_id'] == me).toList();
    final others = statuses.where((s) => s['user_id'] != me).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('GG Status', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))],
      ),
      body: RefreshIndicator(
        onRefresh: load,
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  if (posting) const LinearProgressIndicator(),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('My Status', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            children: [
                              FilledButton.icon(onPressed: posting ? null : createText, icon: const Icon(Icons.edit), label: const Text('Text')),
                              OutlinedButton.icon(onPressed: posting ? null : () => pickMedia(false), icon: const Icon(Icons.photo), label: const Text('Photo')),
                              OutlinedButton.icon(onPressed: posting ? null : () => pickMedia(true), icon: const Icon(Icons.videocam), label: const Text('Video')),
                            ],
                          ),
                          if (mine.isNotEmpty)
                            SizedBox(
                              height: 118,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: mine.length,
                                separatorBuilder: (_, __) => const SizedBox(width: 10),
                                itemBuilder: (_, i) => _Tile(
                                  status: mine[i],
                                  label: 'My Status',
                                  unread: false,
                                  onTap: () => viewStatus(mine[i]),
                                  onDelete: () => deleteStatus(mine[i]),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 18, 4, 8),
                    child: Text('Recent updates', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  if (others.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('No recent status updates'))),
                  for (final status in others)
                    Card(
                      child: ListTile(
                        leading: _Avatar(url: profiles[status['user_id'].toString()]?['avatar_url']?.toString(), unread: !viewed.contains(status['id'].toString())),
                        title: Text(name(status['user_id'].toString()), style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(status['type'] == 'text' ? (status['text'] ?? '') : 'Tap to view ${status['type']} status', maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: viewed.contains(status['id'].toString()) ? const Icon(Icons.done_all, size: 18) : const Icon(Icons.circle, size: 9),
                        onTap: () => viewStatus(status),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final Map<String, dynamic> status;
  final String label;
  final bool unread;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _Tile({required this.status, required this.label, required this.unread, required this.onTap, required this.onDelete});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        onLongPress: onDelete,
        child: SizedBox(
          width: 94,
          child: Column(
            children: [
              Expanded(child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(width: unread ? 3 : 1)), clipBehavior: Clip.antiAlias, child: _Media(status: status))),
              const SizedBox(height: 5),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      );
}

class _Avatar extends StatelessWidget {
  final String? url;
  final bool unread;
  const _Avatar({this.url, required this.unread});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(width: unread ? 3 : 1)),
        child: CircleAvatar(radius: 25, backgroundImage: url != null && url!.isNotEmpty ? NetworkImage(url!) : null, child: url == null || url!.isEmpty ? const Icon(Icons.person) : null),
      );
}

class _Media extends StatelessWidget {
  final Map<String, dynamic> status;
  const _Media({required this.status});
  @override
  Widget build(BuildContext context) {
    final type = status['type'];
    if (type == 'image') return Image.network(status['media_url'] ?? '', fit: BoxFit.cover, width: double.infinity, errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image)));
    if (type == 'video') return const ColoredBox(color: Colors.black87, child: Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 42)));
    return Container(color: Color(int.tryParse((status['background'] ?? '').toString()) ?? 0xff2563eb), alignment: Alignment.center, padding: const EdgeInsets.all(12), child: Text(status['text'] ?? '', maxLines: 6, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)));
  }
}

class _Viewer extends StatefulWidget {
  final Map<String, dynamic> status;
  final SupabaseClient sb;
  final VoidCallback onChanged;
  final bool isMine;
  const _Viewer({required this.status, required this.sb, required this.onChanged, required this.isMine});
  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> {
  String reaction = '';
  List<Map<String, dynamic>> replies = [];
  final TextEditingController reply = TextEditingController();
  bool busy = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    reply.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final rows = await widget.sb.from('status_replies').select('id,user_id,body,created_at').eq('status_id', widget.status['id']).order('created_at');
      final me = widget.sb.auth.currentUser?.id;
      Map<String, dynamic>? mine;
      if (me != null) mine = await widget.sb.from('status_reactions').select('reaction').eq('status_id', widget.status['id']).eq('user_id', me).maybeSingle();
      if (mounted) setState(() { replies = List<Map<String, dynamic>>.from(rows); reaction = mine?['reaction']?.toString() ?? ''; });
    } catch (_) {}
  }

  Future<void> react(String emoji) async {
    final me = widget.sb.auth.currentUser?.id;
    if (me == null) return;
    try {
      if (reaction == emoji) {
        await widget.sb.from('status_reactions').delete().eq('status_id', widget.status['id']).eq('user_id', me);
        setState(() => reaction = '');
      } else {
        await widget.sb.from('status_reactions').upsert({'status_id': widget.status['id'], 'user_id': me, 'reaction': emoji});
        setState(() => reaction = emoji);
      }
    } catch (e) {
      _snack('Reaction failed: $e');
    }
  }

  Future<void> sendReply() async {
    final me = widget.sb.auth.currentUser?.id;
    final text = reply.text.trim();
    if (me == null || text.isEmpty) return;
    setState(() => busy = true);
    try {
      await widget.sb.from('status_replies').insert({'status_id': widget.status['id'], 'user_id': me, 'body': text});
      reply.clear();
      await load();
    } catch (e) {
      _snack('Reply failed: $e');
    }
    if (mounted) setState(() => busy = false);
  }

  void _snack(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(14),
        child: Container(
          decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(20)),
          constraints: const BoxConstraints(maxHeight: 760),
          child: Column(
            children: [
              Align(alignment: Alignment.centerRight, child: IconButton(color: Colors.white, onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close))),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      SizedBox(height: 420, width: double.infinity, child: ClipRRect(borderRadius: BorderRadius.circular(16), child: _Media(status: widget.status))),
                      if (widget.status['type'] == 'text') Padding(padding: const EdgeInsets.all(12), child: Text(widget.status['text'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700))),
                      const SizedBox(height: 8),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: ['❤️', '😂', '👍', '😮', '😢'].map((emoji) => IconButton(onPressed: () => react(emoji), color: reaction == emoji ? Colors.amber : Colors.white, icon: Text(emoji, style: const TextStyle(fontSize: 24))).toList()),
                      const Divider(color: Colors.white24),
                      Align(alignment: Alignment.centerLeft, child: Text('Replies (${replies.length})', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                      ...replies.map((r) => ListTile(dense: true, textColor: Colors.white, title: Text(r['body'] ?? ''), subtitle: Text('${r['created_at'] ?? ''}', style: const TextStyle(color: Colors.white54)))),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                child: Row(children: [
                  Expanded(child: TextField(controller: reply, enabled: !busy, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Reply to status', hintStyle: TextStyle(color: Colors.white54), border: OutlineInputBorder()))),
                  IconButton(onPressed: busy ? null : sendReply, color: Colors.amber, icon: const Icon(Icons.send)),
                ]),
              ),
            ],
          ),
        ),
      );
}
