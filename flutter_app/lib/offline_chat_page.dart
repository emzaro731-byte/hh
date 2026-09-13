import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'call_page.dart';
import 'home_page.dart';
import 'offline_store.dart';

class OfflineChatPage extends StatefulWidget {
  final Conversation conversation;
  final bool dark;
  const OfflineChatPage({super.key, required this.conversation, required this.dark});
  @override
  State<OfflineChatPage> createState() => _OfflineChatPageState();
}

class _OfflineChatPageState extends State<OfflineChatPage> {
  final sb = Supabase.instance.client;
  final input = TextEditingController();
  List<Map<String, dynamic>> messages = [];
  RealtimeChannel? channel;
  RealtimeChannel? presenceChannel;
  String? uid;
  String? peerId;
  bool peerOnline = false;
  bool loading = true;
  bool calling = false;
  bool syncing = false;
  Timer? retryTimer;

  @override
  void initState() {
    super.initState();
    uid = sb.auth.currentUser?.id;
    load();
    retryTimer = Timer.periodic(const Duration(seconds: 8), (_) => syncOutbox());
  }

  Future<void> setupPresence() async {
    if (uid == null) return;
    try {
      peerId ??= await peer();
      final room = 'presence:conversation:${widget.conversation.id}';
      presenceChannel = sb.channel(room, opts: const RealtimeChannelConfig(self: true));
      presenceChannel!
        .onPresenceSync((payload) {
          final state = presenceChannel!.presenceState();
          final onlineIds = <String>{};
          for (final entry in state) {
            for (final presence in entry.presences) {
              final id = '${presence.payload['user_id'] ?? presence.payload['uid'] ?? ''}';
              if (id.isNotEmpty) onlineIds.add(id);
            }
          }
          final online = peerId != null && onlineIds.contains(peerId);
          if (mounted && peerOnline != online) setState(() => peerOnline = online);
        })
        .onPresenceJoin((payload) {
          final online = payload.newPresences.any((p) => '${p.payload['user_id'] ?? p.payload['uid'] ?? ''}' == peerId);
          if (online && mounted) setState(() => peerOnline = true);
        })
        .onPresenceLeave((payload) {
          final left = payload.leftPresences.any((p) => '${p.payload['user_id'] ?? p.payload['uid'] ?? ''}' == peerId);
          if (left && mounted) setState(() => peerOnline = false);
        })
        .subscribe((status, error) async {
          if (status == RealtimeSubscribeStatus.subscribed) {
            await presenceChannel!.track({'user_id': uid, 'online_at': DateTime.now().toUtc().toIso8601String()});
          }
        });
    } catch (_) {}
  }

  Future<void> load() async {
    if (uid == null) {
      if (mounted) setState(() => loading = false);
      return;
    }
    final cached = await OfflineStore.loadMessages(uid!, widget.conversation.id);
    if (mounted) {
      setState(() {
        messages = cached;
        loading = false;
      });
    }
    await setupPresence();
    await syncOutbox();
    try {
      final data = await sb.from('messages').select('*').eq('conversation_id', widget.conversation.id).order('created_at', ascending: true);
      final remote = List<Map<String, dynamic>>.from(data);
      final merged = <String, Map<String, dynamic>>{};
      for (final message in messages) merged['${message['id']}'] = message;
      for (final message in remote) merged['${message['id']}'] = message;
      final combined = merged.values.toList()..sort((a, b) => '${a['created_at']}'.compareTo('${b['created_at']}'));
      messages = combined;
      await OfflineStore.saveMessages(uid!, widget.conversation.id, messages);
      if (mounted) setState(() {});
      channel = sb.channel('chat:${widget.conversation.id}')
        ..onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'conversation_id', value: widget.conversation.id),
          callback: (payload) async {
            final message = Map<String, dynamic>.from(payload.newRecord);
            if (!messages.any((item) => item['id'] == message['id'])) {
              messages.add(message);
              messages.sort((a, b) => '${a['created_at']}'.compareTo('${b['created_at']}'));
              if (mounted) setState(() {});
              await OfflineStore.saveMessages(uid!, widget.conversation.id, messages);
            }
          },
        ).subscribe();
      try {
        await sb.from('messages').update({'read_at': DateTime.now().toUtc().toIso8601String()}).eq('conversation_id', widget.conversation.id).neq('sender_id', uid!).isFilter('read_at', null);
      } catch (_) {}
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  Future<void> syncOutbox() async {
    if (uid == null || syncing) return;
    syncing = true;
    try {
      final pending = await OfflineStore.loadOutbox(uid!);
      for (final item in pending) {
        try {
          final localId = '${item['local_id']}';
          final data = await sb.from('messages').insert({
            'conversation_id': item['conversation_id'],
            'sender_id': item['sender_id'],
            'body': item['body'],
            'message_type': item['message_type'] ?? 'text',
            'delivered_at': DateTime.now().toUtc().toIso8601String(),
          }).select().single();
          await OfflineStore.removeOutbox(uid!, localId);
          final server = Map<String, dynamic>.from(data);
          final index = messages.indexWhere((m) => m['id'] == localId);
          if (index >= 0) {
            messages[index] = server;
          } else if ('${server['conversation_id']}' == widget.conversation.id && !messages.any((m) => m['id'] == server['id'])) {
            messages.add(server);
          }
          messages.sort((a, b) => '${a['created_at']}'.compareTo('${b['created_at']}'));
          await OfflineStore.saveMessages(uid!, widget.conversation.id, messages);
          if (mounted && '${item['conversation_id']}' == widget.conversation.id) setState(() {});
        } catch (_) {
          break;
        }
      }
    } finally {
      syncing = false;
    }
  }

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty || uid == null) return;
    input.clear();
    final localId = 'local_${DateTime.now().microsecondsSinceEpoch}';
    final local = <String, dynamic>{
      'id': localId,
      'conversation_id': widget.conversation.id,
      'sender_id': uid,
      'body': text,
      'message_type': 'text',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      '_pending': true,
      '_offline': true,
    };
    setState(() => messages.add(local));
    await OfflineStore.saveMessages(uid!, widget.conversation.id, messages);
    await OfflineStore.addOutbox(uid!, {
      'local_id': localId,
      'conversation_id': widget.conversation.id,
      'sender_id': uid,
      'body': text,
      'message_type': 'text',
      'created_at': local['created_at'],
    });
    await syncOutbox();
  }

  Future<String?> peer() async {
    if (uid == null) return null;
    final rows = await sb.from('conversation_members').select('user_id').eq('conversation_id', widget.conversation.id).neq('user_id', uid!).limit(1);
    return rows.isEmpty ? null : rows.first['user_id']?.toString();
  }

  Future<void> call(bool video) async {
    if (calling || uid == null) return;
    try {
      setState(() => calling = true);
      final peerId = await peer();
      if (peerId == null) throw Exception('Other participant not found');
      final data = await sb.from('calls').insert({'caller_id': uid, 'callee_id': peerId, 'type': video ? 'video' : 'audio', 'status': 'ringing'}).select().single();
      if (mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => CallPage(callId: data['id'].toString(), video: video, caller: true)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Call failed: $e')));
    } finally {
      if (mounted) setState(() => calling = false);
    }
  }

  String time(dynamic value) {
    try { return TimeOfDay.fromDateTime(DateTime.parse(value.toString()).toLocal()).format(context); } catch (_) { return ''; }
  }

  String day(dynamic value) {
    try {
      final date = DateTime.parse(value.toString()).toLocal();
      final now = DateTime.now();
      if (date.year == now.year && date.month == now.month && date.day == now.day) return 'Today';
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) { return ''; }
  }

  Future<void> open(dynamic value) async {
    if (value == null || value.toString().isEmpty) return;
    await launchUrl(Uri.parse(value.toString()), mode: LaunchMode.externalApplication);
  }

  Widget messageStatus(Map<String, dynamic> message) {
    if (message['_pending'] == true) {
      return const Icon(Icons.schedule_rounded, size: 14, color: Colors.white70);
    }
    final read = message['read_at'] != null && '${message['read_at']}'.isNotEmpty;
    if (read) {
      return const Icon(Icons.done_all_rounded, size: 15, color: Color(0xffffc107));
    }
    // GG status: offline = one check, online/delivered = double checks.
    if (peerOnline) {
      return const Icon(Icons.done_all_rounded, size: 15, color: Colors.white70);
    }
    return const Icon(Icons.done_rounded, size: 15, color: Colors.white70);
  }

  Widget bubble(Map<String, dynamic> message) {
    final mine = message['sender_id'] == uid;
    final type = '${message['message_type'] ?? 'text'}';
    final url = message['file_url'] ?? message['url'] ?? message['media_url'];
    final offline = message['_offline'] == true;
    final foreground = mine ? Colors.white : null;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        margin: EdgeInsets.only(left: mine ? 48 : 4, right: mine ? 4 : 48, bottom: 6),
        padding: const EdgeInsets.fromLTRB(13, 10, 11, 7),
        decoration: BoxDecoration(color: mine ? const Color(0xff2563eb) : (widget.dark ? const Color(0xff202938) : const Color(0xffe8edf5)), borderRadius: BorderRadius.only(topLeft: const Radius.circular(18), topRight: const Radius.circular(18), bottomLeft: Radius.circular(mine ? 18 : 5), bottomRight: Radius.circular(mine ? 5 : 18))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (url != null && type.contains('image')) ClipRRect(borderRadius: BorderRadius.circular(13), child: GestureDetector(onTap: () => open(url), child: Image.network(url.toString(), height: 190, width: 300, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(height: 100, child: Center(child: Icon(Icons.broken_image_outlined))))))
          else if (url != null) InkWell(onTap: () => open(url), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(type.contains('video') ? Icons.play_circle_fill : type.contains('audio') ? Icons.headphones : Icons.insert_drive_file, color: foreground), const SizedBox(width: 8), Flexible(child: Text('${message['file_name'] ?? 'Open attachment'}', style: TextStyle(color: foreground, fontWeight: FontWeight.w600)))])),
          if ((message['body'] ?? '').toString().isNotEmpty && (url == null || type == 'text')) Text('${message['body']}', style: TextStyle(color: foreground, fontSize: 16, height: 1.3)),
          const SizedBox(height: 3),
          Row(mainAxisSize: MainAxisSize.min, children: [Text(time(message['created_at']), style: TextStyle(color: mine ? Colors.white70 : Colors.grey, fontSize: 10)), if (mine) Padding(padding: const EdgeInsets.only(left: 5), child: offline && message['_pending'] == true ? const Icon(Icons.cloud_off_rounded, size: 14, color: Colors.white70) : messageStatus(message))]),
        ]),
      ),
    );
  }

  @override
  void dispose() {
    retryTimer?.cancel();
    if (channel != null) sb.removeChannel(channel!);
    if (presenceChannel != null) sb.removeChannel(presenceChannel!);
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.dark ? ThemeData.dark(useMaterial3: true) : ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xff2563eb));
    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: widget.dark ? const Color(0xff0f1117) : const Color(0xfff7f8fc),
        appBar: AppBar(
          titleSpacing: 0,
          title: Row(children: [CircleAvatar(radius: 21, child: Text(widget.conversation.name.isEmpty ? 'G' : widget.conversation.name[0].toUpperCase())), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(widget.conversation.name, style: const TextStyle(fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis), Text(syncing ? 'Syncing messages…' : peerOnline ? 'Online' : 'Offline', style: TextStyle(fontSize: 11, color: peerOnline ? const Color(0xff22c55e) : Theme.of(context).colorScheme.onSurfaceVariant))]))]),
          actions: [IconButton(onPressed: calling ? null : () => call(false), icon: const Icon(Icons.call_rounded)), IconButton(onPressed: calling ? null : () => call(true), icon: const Icon(Icons.videocam_rounded)), const SizedBox(width: 4)],
        ),
        body: Column(children: [
          Expanded(child: loading ? const Center(child: CircularProgressIndicator()) : messages.isEmpty ? const Center(child: Text('No messages yet')) : ListView.builder(padding: const EdgeInsets.fromLTRB(10, 14, 10, 10), itemCount: messages.length, itemBuilder: (_, index) { final message = messages[index]; final previous = index > 0 ? messages[index - 1] : null; final showDay = previous == null || day(previous['created_at']) != day(message['created_at']); return Column(children: [if (showDay) Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Chip(label: Text(day(message['created_at']), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)))), bubble(message)]); })),
          SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(7, 5, 7, 8), child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [IconButton(onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Attachments require a configured chat-media bucket.'))), icon: const Icon(Icons.add_circle_outline)), Expanded(child: TextField(controller: input, minLines: 1, maxLines: 5, textInputAction: TextInputAction.newline, decoration: InputDecoration(hintText: 'Message', prefixIcon: const Icon(Icons.emoji_emotions_outlined), suffixIcon: IconButton(onPressed: () => input.clear(), icon: const Icon(Icons.close, size: 18)), filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(26), borderSide: BorderSide.none)))), const SizedBox(width: 5), ValueListenableBuilder<TextEditingValue>(valueListenable: input, builder: (_, value, __) { final hasText = value.text.trim().isNotEmpty; return FloatingActionButton.small(onPressed: hasText ? send : null, child: Icon(hasText ? Icons.send_rounded : Icons.mic_rounded)); })]))),
        ]),
      ),
    );
  }
}
