import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_page.dart';
import 'call_page.dart';
import 'offline_store.dart';

class ChatPage extends StatefulWidget {
  final Conversation conversation;
  final bool dark;
  const ChatPage({super.key, required this.conversation, required this.dark});
  @override State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final sb = Supabase.instance.client;
  final input = TextEditingController();
  final recorder = AudioRecorder();
  final player = AudioPlayer();
  final messages = <Map<String, dynamic>>[];
  RealtimeChannel? channel;
  Timer? timer;
  String? uid;
  bool loading = true, recording = false, busy = false, calling = false;

  @override
  void initState() { super.initState(); uid = sb.auth.currentUser?.id; load(); timer = Timer.periodic(const Duration(seconds: 30), (_) => flush()); }

  Future<void> cache() async { if (uid != null) await OfflineStore.saveMessages(uid!, widget.conversation.id, messages); }

  Future<void> load() async {
    if (uid != null) {
      final saved = await OfflineStore.loadMessages(uid!, widget.conversation.id);
      if (saved.isNotEmpty && mounted) setState(() { messages..clear()..addAll(saved); loading = false; });
    }
    try {
      final data = await sb.from('messages').select('*').eq('conversation_id', widget.conversation.id).order('created_at');
      messages..clear()..addAll(List<Map<String, dynamic>>.from(data));
      await cache();
      channel = sb.channel('chat_${widget.conversation.id}').onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'messages', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'conversation_id', value: widget.conversation.id), callback: (p) { final m = Map<String, dynamic>.from(p.newRecord); if (!messages.any((x) => x['id'] == m['id'])) { messages.add(m); cache(); if (mounted) setState(() {}); } }).subscribe();
      await flush();
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<void> flush() async {
    if (uid == null) return;
    for (final item in await OfflineStore.loadOutbox(uid!)) {
      try {
        final row = await sb.from('messages').insert({'conversation_id': item['conversation_id'], 'sender_id': uid, 'body': item['body'], 'message_type': 'text', 'delivered_at': DateTime.now().toUtc().toIso8601String()}).select().single();
        await OfflineStore.removeOutbox(uid!, '${item['local_id']}');
        if ('${item['conversation_id']}' == widget.conversation.id) { messages.removeWhere((m) => m['id'] == item['local_id']); messages.add(Map<String, dynamic>.from(row)); await cache(); if (mounted) setState(() {}); }
      } catch (_) {}
    }
  }

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty || uid == null) return;
    input.clear();
    final id = 'local_${DateTime.now().microsecondsSinceEpoch}';
    messages.add({'id': id, 'conversation_id': widget.conversation.id, 'sender_id': uid, 'body': text, 'message_type': 'text', 'created_at': DateTime.now().toUtc().toIso8601String(), '_offline': true});
    await OfflineStore.addOutbox(uid!, {'local_id': id, 'conversation_id': widget.conversation.id, 'body': text});
    await cache();
    if (mounted) setState(() {});
    await flush();
  }

  Future<void> attach() async {
    final type = await showModalBottomSheet<String>(context: context, builder: (c) => SafeArea(child: Wrap(children: [
      ListTile(leading: const Icon(Icons.photo), title: const Text('Photo / Video'), onTap: () => Navigator.pop(c, 'media')),
      ListTile(leading: const Icon(Icons.insert_drive_file), title: const Text('Document / File'), onTap: () => Navigator.pop(c, 'file')),
      ListTile(leading: const Icon(Icons.mic), title: const Text('Voice message'), onTap: () => Navigator.pop(c, 'voice')),
    ])));
    if (type == null) return;
    if (type == 'voice') { await recordVoice(); return; }
    if (uid == null) return;
    try {
      late String path; late String name; late String kind;
      if (type == 'media') {
        final p = await ImagePicker().pickMedia(); if (p == null) return;
        name = p.name; kind = (p.mimeType ?? '').startsWith('video/') ? 'video' : 'image'; path = '${uid!}/${DateTime.now().millisecondsSinceEpoch}_$name';
        await sb.storage.from('chat-media').upload(path, File(p.path));
      } else {
        final p = await FilePicker.platform.pickFiles(); if (p == null || p.files.single.path == null) return;
        name = p.files.single.name; kind = 'file'; path = '${uid!}/${DateTime.now().millisecondsSinceEpoch}_$name';
        await sb.storage.from('chat-media').upload(path, File(p.files.single.path!));
      }
      final url = await sb.storage.from('chat-media').createSignedUrl(path, 604800);
      final row = await sb.from('messages').insert({'conversation_id': widget.conversation.id, 'sender_id': uid, 'body': name, 'message_type': kind, 'media_url': url, 'file_name': name}).select().single();
      messages.add(Map<String, dynamic>.from(row)); await cache(); if (mounted) setState(() {});
    } catch (e) { snack('Attachment failed: $e'); }
  }

  Future<void> recordVoice() async {
    if (recording) {
      setState(() => busy = true);
      try { final path = await recorder.stop(); setState(() => recording = false); if (path != null) await uploadVoice(path); }
      catch (e) { snack('Recording failed: $e'); }
      finally { if (mounted) setState(() => busy = false); }
      return;
    }
    if (!await recorder.hasPermission()) { snack('Microphone permission is required.'); return; }
    try { await recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 44100, bitRate: 128000, numChannels: 1), path: '${Directory.systemTemp.path}/gg_voice.m4a'); setState(() => recording = true); }
    catch (e) { snack('Could not start recording: $e'); }
  }

  Future<void> uploadVoice(String localPath) async {
    if (uid == null) return;
    try {
      final name = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final path = '${uid!}/$name';
      await sb.storage.from('chat-media').upload(path, File(localPath));
      final url = await sb.storage.from('chat-media').createSignedUrl(path, 604800);
      final row = await sb.from('messages').insert({'conversation_id': widget.conversation.id, 'sender_id': uid, 'body': name, 'message_type': 'voice', 'media_url': url, 'file_name': name}).select().single();
      messages.add(Map<String, dynamic>.from(row)); await cache(); if (mounted) setState(() {});
    } catch (e) { snack('Voice upload failed: $e'); }
  }

  Future<void> playVoice(String url) async { try { await player.stop(); await player.setUrl(url); await player.play(); } catch (e) { snack('Audio playback failed: $e'); } }

  Future<void> startCall(bool video) async {
    if (calling || uid == null) return;
    try {
      setState(() => calling = true);
      final rows = await sb.from('conversation_members').select('user_id').eq('conversation_id', widget.conversation.id).neq('user_id', uid!).limit(1);
      if (rows.isEmpty) throw Exception('Other participant not found');
      final row = await sb.from('calls').insert({'caller_id': uid, 'callee_id': rows.first['user_id'], 'type': video ? 'video' : 'audio', 'status': 'ringing'}).select().single();
      try { await sb.functions.invoke('send-call-push', body: {'callId': row['id']}); } catch (_) {}
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => CallPage(callId: '${row['id']}', video: video, caller: true)));
    } catch (e) { snack('Call failed: $e'); }
    finally { if (mounted) setState(() => calling = false); }
  }

  void snack(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  String time(dynamic v) { try { return TimeOfDay.fromDateTime(DateTime.parse('$v').toLocal()).format(context); } catch (_) { return ''; } }

  @override
  void dispose() { timer?.cancel(); recorder.dispose(); player.dispose(); input.dispose(); if (channel != null) sb.removeChannel(channel!); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final theme = widget.dark ? ThemeData.dark(useMaterial3: true) : ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xff2563eb));
    return Theme(data: theme, child: Scaffold(
      appBar: AppBar(title: Text(widget.conversation.name), actions: [IconButton(onPressed: calling ? null : () => startCall(false), icon: const Icon(Icons.call)), IconButton(onPressed: calling ? null : () => startCall(true), icon: const Icon(Icons.videocam))]),
      body: Column(children: [
        Expanded(child: loading ? const Center(child: CircularProgressIndicator()) : ListView.builder(itemCount: messages.length, padding: const EdgeInsets.all(12), itemBuilder: (_, i) {
          final m = messages[i]; final mine = m['sender_id'] == uid; final kind = m['message_type'];
          Widget body = Text('${m['body'] ?? ''}', style: TextStyle(color: mine ? Colors.white : null));
          if (kind == 'image' && m['media_url'] != null) body = Image.network('${m['media_url']}', height: 220, fit: BoxFit.cover);
          if (kind == 'file' || kind == 'video') body = Row(children: [const Icon(Icons.insert_drive_file), const SizedBox(width: 8), Text('${m['file_name'] ?? kind}')]);
          if (kind == 'voice' && m['media_url'] != null) body = InkWell(onTap: () => playVoice('${m['media_url']}'), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.play_arrow), Text('Voice message')]));
          return Align(alignment: mine ? Alignment.centerRight : Alignment.centerLeft, child: Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12), constraints: const BoxConstraints(maxWidth: 340), decoration: BoxDecoration(color: mine ? const Color(0xff2563eb) : Colors.grey.shade200, borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [body, const SizedBox(height: 4), Text(time(m['created_at']), style: const TextStyle(fontSize: 10))])));
        })),
        SafeArea(child: Row(children: [IconButton(onPressed: busy ? null : attach, icon: const Icon(Icons.add_circle_outline)), Expanded(child: TextField(controller: input, onSubmitted: (_) => send(), decoration: const InputDecoration(hintText: 'Message'))), IconButton(onPressed: busy ? null : recordVoice, icon: Icon(recording ? Icons.stop_circle : Icons.mic, color: recording ? Colors.red : null)), IconButton(onPressed: recording || busy ? null : send, icon: const Icon(Icons.send, color: Color(0xff2563eb)))])),
      ]),
    ));
  }
}
