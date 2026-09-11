import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_page.dart';

class ChatPage extends StatefulWidget {
  final Conversation conversation;
  final bool dark;
  const ChatPage({super.key, required this.conversation, required this.dark});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final sb = Supabase.instance.client;
  final input = TextEditingController();
  List<Map<String, dynamic>> messages = [];
  bool loading = true;
  late RealtimeChannel channel;
  String? uid;

  @override
  void initState() {
    super.initState();
    uid = sb.auth.currentUser?.id;
    load();
  }

  Future<void> load() async {
    try {
      final d = await sb.from('messages').select('*').eq('conversation_id', widget.conversation.id).order('created_at', ascending: true);
      if (mounted) setState(() => messages = List<Map<String, dynamic>>.from(d));
      channel = sb.channel('messages:${widget.conversation.id}');
      channel.onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'messages', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'conversation_id', value: widget.conversation.id), callback: (p) {
        final m = Map<String, dynamic>.from(p.newRecord);
        if (m['id'] != null && !messages.any((x) => x['id'] == m['id']) && mounted) setState(() => messages.add(m));
      }).subscribe();
      if (uid != null) {
        await sb.from('messages').update({'read_at': DateTime.now().toUtc().toIso8601String()}).eq('conversation_id', widget.conversation.id).neq('sender_id', uid!).isFilter('read_at', null);
      }
    } catch (e) {
      snack(e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty || uid == null) return;
    input.clear();
    try {
      final m = await sb.from('messages').insert({'conversation_id': widget.conversation.id, 'sender_id': uid, 'body': text, 'message_type': 'text', 'delivered_at': DateTime.now().toUtc().toIso8601String()}).select().single();
      if (mounted && !messages.any((x) => x['id'] == m['id'])) setState(() => messages.add(Map<String, dynamic>.from(m)));
    } catch (e) {
      input.text = text;
      snack(e.toString());
    }
  }

  Future<void> attach() async {
    final type = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        TextButton(onPressed: () => Navigator.pop(context, 'image'), child: const Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.image), Text('Photo')])),
        TextButton(onPressed: () => Navigator.pop(context, 'file'), child: const Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.insert_drive_file), Text('File')])),
      ])),
    );
    if (type == null || uid == null) return;
    try {
      String path, name, kind;
      if (type == 'image') {
        final p = await ImagePicker().pickImage(source: ImageSource.gallery);
        if (p == null) return;
        name = p.name;
        kind = 'image';
        path = '${uid!}/${DateTime.now().millisecondsSinceEpoch}_$name';
        await sb.storage.from('chat-media').upload(path, File(p.path));
      } else {
        final p = await FilePicker.platform.pickFiles();
        if (p == null || p.files.single.path == null) return;
        name = p.files.single.name;
        kind = 'file';
        path = '${uid!}/${DateTime.now().millisecondsSinceEpoch}_$name';
        await sb.storage.from('chat-media').upload(path, File(p.files.single.path!));
      }
      final url = await sb.storage.from('chat-media').createSignedUrl(path, 604800);
      final m = await sb.from('messages').insert({'conversation_id': widget.conversation.id, 'sender_id': uid, 'body': name, 'message_type': kind, 'media_url': url, 'file_name': name, 'delivered_at': DateTime.now().toUtc().toIso8601String()}).select().single();
      if (mounted) setState(() => messages.add(Map<String, dynamic>.from(m)));
    } catch (e) {
      snack('Attachment failed: $e');
    }
  }

  void snack(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  String time(dynamic v) {
    if (v == null) return '';
    return TimeOfDay.fromDateTime(DateTime.parse(v.toString()).toLocal()).format(context);
  }

  @override
  void dispose() {
    try { sb.removeChannel(channel); } catch (_) {}
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    return Theme(
      data: widget.dark ? ThemeData.dark(useMaterial3: true) : ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xff2563eb)),
      child: Scaffold(
        appBar: AppBar(
          title: Row(children: [CircleAvatar(child: Text(widget.conversation.name.isEmpty ? 'G' : widget.conversation.name[0])), const SizedBox(width: 10), Text(widget.conversation.name)]),
          actions: [
            IconButton(onPressed: () => snack('Connect flutter_webrtc to the existing calls tables for live voice.'), icon: const Icon(Icons.call)),
            IconButton(onPressed: () => snack('Connect flutter_webrtc to the existing calls tables for live video.'), icon: const Icon(Icons.videocam)),
          ],
        ),
        body: Column(children: [
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length,
                    itemBuilder: (_, i) {
                      final m = messages[i];
                      final mine = m['sender_id'] == uid;
                      return Align(
                        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 330),
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: mine ? const Color(0xff2563eb) : (widget.dark ? const Color(0xff202938) : const Color(0xffe7ebf2)), borderRadius: BorderRadius.circular(16)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            if (m['message_type'] == 'image' && m['media_url'] != null) Image.network(m['media_url'].toString(), height: 220, fit: BoxFit.cover),
                            if (m['message_type'] == 'file') Row(children: [const Icon(Icons.insert_drive_file), const SizedBox(width: 8), Expanded(child: Text(m['file_name'] ?? 'Document'))]),
                            if (m['message_type'] == 'text') Text(m['body'] ?? '', style: TextStyle(color: mine ? Colors.white : null, fontSize: 15)),
                            const SizedBox(height: 4),
                            Text(time(m['created_at']), style: TextStyle(color: mine ? Colors.white70 : Colors.grey, fontSize: 10)),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(child: Padding(padding: const EdgeInsets.all(8), child: Row(children: [
            IconButton(onPressed: attach, icon: const Icon(Icons.add_circle_outline)),
            Expanded(child: TextField(controller: input, textInputAction: TextInputAction.send, onSubmitted: (_) => send(), decoration: InputDecoration(hintText: 'Message', filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(24))))),
            IconButton(onPressed: send, icon: const Icon(Icons.send, color: Color(0xff2563eb))),
          ]))),
        ]),
      ),
    );
  }
}
