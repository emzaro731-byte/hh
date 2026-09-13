import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
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
  Timer? syncTimer;
  String? uid;
  bool loading = true, calling = false, recording = false, uploading = false;

  @override
  void initState() { super.initState(); uid = sb.auth.currentUser?.id; load(); syncTimer = Timer.periodic(const Duration(seconds: 30), (_) => flushOutbox()); }

  Future<void> saveCache() async { if (uid != null) await OfflineStore.saveMessages(uid!, widget.conversation.id, messages); }

  Future<void> load() async {
    if (uid != null) {
      final cached = await OfflineStore.loadMessages(uid!, widget.conversation.id);
      if (cached.isNotEmpty && mounted) setState(() { messages.addAll(cached); loading = false; });
    }
    try {
      final data = await sb.from('messages').select('*').eq('conversation_id', widget.conversation.id).order('created_at', ascending: true);
      final merged = <String, Map<String, dynamic>>{};
      for (final m in messages) { if (m['id'] != null) merged['${m['id']}'] = m; }
      for (final m in List<Map<String, dynamic>>.from(data)) { if (m['id'] != null) merged['${m['id']}'] = Map<String, dynamic>.from(m); }
      messages..clear()..addAll(merged.values)..sort((a, b) => '${a['created_at'] ?? ''}'.compareTo('${b['created_at'] ?? ''}'));
      await saveCache();
      channel = sb.channel('messages:${widget.conversation.id}');
      channel!.onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'messages', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'conversation_id', value: widget.conversation.id), callback: (payload) async {
        final m = Map<String, dynamic>.from(payload.newRecord);
        if (m['id'] != null && !messages.any((x) => x['id'] == m['id'])) { messages.add(m); await saveCache(); if (mounted) setState(() {}); }
      }).subscribe();
      if (uid != null) await sb.from('messages').update({'read_at': DateTime.now().toUtc().toIso8601String()}).eq('conversation_id', widget.conversation.id).neq('sender_id', uid!).isFilter('read_at', null);
      await flushOutbox();
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  Future<void> flushOutbox() async {
    if (uid == null) return;
    final items = await OfflineStore.loadOutbox(uid!);
    for (final item in items) {
      try {
        final m = await sb.from('messages').insert({'conversation_id': item['conversation_id'], 'sender_id': uid, 'body': item['body'], 'message_type': 'text', 'delivered_at': DateTime.now().toUtc().toIso8601String()}).select().single();
        await OfflineStore.removeOutbox(uid!, '${item['local_id']}');
        if ('${item['conversation_id']}' == widget.conversation.id) { messages.removeWhere((x) => x['id'] == item['local_id']); messages.add(Map<String, dynamic>.from(m)); await saveCache(); if (mounted) setState(() {}); }
      } catch (_) {}
    }
  }

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty || uid == null) return;
    input.clear();
    final localId = 'local_${DateTime.now().microsecondsSinceEpoch}';
    messages.add({'id': localId, 'conversation_id': widget.conversation.id, 'sender_id': uid, 'body': text, 'message_type': 'text', 'created_at': DateTime.now().toUtc().toIso8601String(), '_offline': true});
    await OfflineStore.addOutbox(uid!, {'local_id': localId, 'conversation_id': widget.conversation.id, 'body': text});
    await saveCache();
    if (mounted) setState(() {});
    await flushOutbox();
  }

  Future<void> attach() async {
    final type = await showModalBottomSheet<String>(context: context, builder: (_) => SafeArea(child: Wrap(children: [
      ListTile(leading: const Icon(Icons.photo), title: const Text('Photo / Video'), onTap: () => Navigator.pop(context, 'media')),
      ListTile(leading: const Icon(Icons.insert_drive_file), title: const Text('Document / File'), onTap: () => Navigator.pop(context, 'file')),
      ListTile(leading: const Icon(Icons.mic), title: const Text('Voice message'), onTap: () => Navigator.pop(context, 'voice')),
    ])));
    if (type == null || uid == null) return;
    if (type == 'voice') { await toggleRecording(); return; }
    try {
      String path, name, kind;
      String? mime;
      if (type == 'media') {
        final p = await ImagePicker().pickMedia();
        if (p == null) return;
        name = p.name; mime = p.mimeType; kind = (mime ?? '').startsWith('video/') ? 'video' : 'image';
        path = '${uid!}/${DateTime.now().millisecondsSinceEpoch}_$name';
        await sb.storage.from('chat-media').upload(path, File(p.path), fileOptions: FileOptions(contentType: mime));
      } else {
        final p = await FilePicker.platform.pickFiles();
        if (p == null || p.files.single.path == null) return;
        name = p.files.single.name; kind = 'file'; path = '${uid!}/${DateTime.now().millisecondsSinceEpoch}_$name';
        await sb.storage.from('chat-media').upload(path, File(p.files.single.path!), fileOptions: const FileOptions(contentType: 'application/octet-stream'));
      }
      final url = await sb.storage.from('chat-media').createSignedUrl(path, 604800);
      final m = await sb.from('messages').insert({'conversation_id': widget.conversation.id, 'sender_id': uid, 'body': name, 'message_type': kind, 'media_url': url, 'file_name': name, 'delivered_at': DateTime.now().toUtc().toIso8601String()}).select().single();
      messages.add(Map<String, dynamic>.from(m)); await saveCache(); if (mounted) setState(() {});
    } catch (e) { snack('Attachment failed: $e'); }
  }

  Future<void> toggleRecording() async {
    if (recording) {
      if (mounted) setState(() => uploading = true);
      try { final path = await recorder.stop(); if (mounted) setState(() => recording = false); if (path != null) await sendVoice(path); }
      catch (e) { if (mounted) setState(() => recording = false); snack('Recording failed: $e'); }
      finally { if (mounted) setState(() => uploading = false); }
      return;
    }
    if (!await recorder.hasPermission()) { snack('Allow microphone permission for voice messages.'); return; }
    try {
      final path = '${Directory.systemTemp.path}/gg_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 44100, bitRate: 128000, numChannels: 1), path: path);
      if (mounted) setState(() => recording = true);
    } catch (e) { snack('Could not start microphone: $e'); }
  }

  Future<void> sendVoice(String localPath) async {
    if (uid == null) return;
    try {
      final name = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final path = '${uid!}/$name';
      await sb.storage.from('chat-media').upload(path, File(localPath), fileOptions: const FileOptions(contentType: 'audio/mp4'));
      final url = await sb.storage.from('chat-media').createSignedUrl(path, 604800);
      final m = await sb.from('messages').insert({'conversation_id': widget.conversation.id, 'sender_id': uid, 'body': name, 'message_type': 'voice', 'media_url': url, 'file_name': name, 'delivered_at': DateTime.now().toUtc().toIso8601String()}).select().single();
      messages.add(Map<String, dynamic>.from(m)); await saveCache(); if (mounted) setState(() {});
      try { await File(localPath).delete(); } catch (_) {}
    } catch (e) { snack('Voice upload failed: $e'); }
  }

  Future<void> playVoice(String url) async { try { await player.stop(); await player.setUrl(url); await player.play(); } catch (e) { snack('Audio playback failed: $e'); } }

  Future<String?> peerId() async {
    final me = sb.auth.currentUser?.id;
    if (me == null) return null;
    final rows = await sb.from('conversation_members').select('user_id').eq('conversation_id', widget.conversation.id).neq('user_id', me).limit(1);
    return rows.isEmpty ? null : '${rows.first['user_id']}';
  }

  Future<void> startCall({required bool video}) async {
    if (calling) return;
    try {
      if (mounted) setState(() => calling = true);
      final peer = await peerId();
      if (peer == null) throw Exception('Could not find the other participant.');
      final row = await sb.from('calls').insert({'caller_id': uid, 'callee_id': peer, 'type': video ? 'video' : 'audio', 'status': 'ringing'}).select().single();
      try { await sb.functions.invoke('send-call-push', body: {'callId': row['id']}); } catch (_) {}
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => CallPage(callId: '${row['id']}', video: video, caller: true)));
    } catch (e) { if (mounted) snack('Call failed: $e'); }
    finally { if (mounted) setState(() => calling = false); }
  }

  void snack(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  String time(dynamic value) { if (value == null) return ''; try { return TimeOfDay.fromDateTime(DateTime.parse(value.toString()).toLocal()).format(context); } catch (_) { return ''; } }

  Widget messageBubble(Map<String, dynamic> m) {
    final mine = m['sender_id'] == uid;
    final kind = '${m['message_type'] ?? 'text'}';
    Widget content;
    if (kind == 'image' && m['media_url'] != null) {
      content = Image.network('${m['media_url']}', height: 220, width: 300, fit: BoxFit.cover);
    } else if (kind == 'video') {
      content = Row(children: [const Icon(Icons.play_circle_fill, size: 42), const SizedBox(width: 8), Expanded(child: Text('${m['file_name'] ?? 'Video'}'))]);
    } else if (kind == 'file') {
      content = Row(children: [const Icon(Icons.insert_drive_file), const SizedBox(width: 8), Expanded(child: Text('${m['file_name'] ?? 'Document'}'))]);
    } else if (kind == 'voice' && m['media_url'] != null) {
      content = InkWell(onTap: () => playVoice('${m['media_url']}'), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.play_arrow), SizedBox(width: 6), Text('Voice message')]));
    } else {
      content = Text('${m['body'] ?? ''}', style: TextStyle(color: mine ? Colors.white : null, fontSize: 15));
    }
    return Align(alignment: mine ? Alignment.centerRight : Alignment.centerLeft, child: Container(constraints: const BoxConstraints(maxWidth: 340), margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: mine ? const Color(0xff2563eb) : (widget.dark ? const Color(0xff202938) : const Color(0xffe7ebf2)), borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [content, const SizedBox(height: 4), Row(mainAxisSize: MainAxisSize.min, children: [Text(time(m['created_at']), style: TextStyle(color: mine ? Colors.white70 : Colors.grey, fontSize: 10)), if (m['_offline'] == true) const Padding(padding: EdgeInsets.only(left: 5), child: Icon(Icons.cloud_off, size: 13))])])));
  }

  @override
  void dispose() { syncTimer?.cancel(); recorder.dispose(); player.dispose(); if (channel != null) sb.removeChannel(channel!); input.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final theme = widget.dark ? ThemeData.dark(useMaterial3: true) : ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xff2563eb));
    return Theme(data: theme, child: Scaffold(
      appBar: AppBar(title: Row(children: [CircleAvatar(child: Text(widget.conversation.name.isEmpty ? 'G' : widget.conversation.name[0])), const SizedBox(width: 10), Expanded(child: Text(widget.conversation.name, overflow: TextOverflow.ellipsis))]), actions: [
        IconButton(tooltip: 'Voice call', onPressed: calling ? null : () => startCall(video: false), icon: const Icon(Icons.call)),
        IconButton(tooltip: 'Video call', onPressed: calling ? null : () => startCall(video: true), icon: const Icon(Icons.videocam)),
      ]),
      body: Column(children: [
        Expanded(child: loading ? const Center(child: CircularProgressIndicator()) : ListView.builder(padding: const EdgeInsets.all(12), itemCount: messages.length, itemBuilder: (_, i) => messageBubble(messages[i]))),
        SafeArea(child: Padding(padding: const EdgeInsets.all(8), child: Row(children: [
          IconButton(onPressed: uploading ? null : attach, icon: Icon(recording ? Icons.stop_circle : Icons.add_circle_outline, color: recording ? Colors.red : null)),
          Expanded(child: TextField(controller: input, textInputAction: TextInputAction.send, onChanged: (_) => setState(() {}), onSubmitted: (_) => send(), decoration: InputDecoration(hintText: recording ? 'Recording… tap stop when finished' : 'Message', filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(24))))),
          IconButton(onPressed: uploading ? null : (input.text.trim().isNotEmpty ? send : toggleRecording), icon: Icon(recording ? Icons.stop : (input.text.trim().isNotEmpty ? Icons.send : Icons.mic), color: recording ? Colors.red : const Color(0xff2563eb))),
        ]))),
      ]),
    ));
  }
}
