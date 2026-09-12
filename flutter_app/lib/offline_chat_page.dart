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
  String? uid;
  bool loading = true;
  bool calling = false;

  @override
  void initState() {
    super.initState();
    uid = sb.auth.currentUser?.id;
    load();
  }

  Future<void> load() async {
    if (uid == null) {
      if (mounted) setState(() => loading = false);
      return;
    }

    final cached = await OfflineStore.loadMessages(uid!, widget.conversation.id);
    if (mounted && cached.isNotEmpty) {
      setState(() {
        messages = cached;
        loading = false;
      });
    }

    try {
      final data = await sb
          .from('messages')
          .select('*')
          .eq('conversation_id', widget.conversation.id)
          .order('created_at', ascending: true);
      messages = List<Map<String, dynamic>>.from(data);
      await OfflineStore.saveMessages(uid!, widget.conversation.id, messages);
      if (mounted) setState(() => loading = false);

      channel = sb.channel('chat:${widget.conversation.id}')
        ..onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: widget.conversation.id,
          ),
          callback: (payload) async {
            final message = Map<String, dynamic>.from(payload.newRecord);
            if (!messages.any((item) => item['id'] == message['id'])) {
              messages.add(message);
              if (mounted) setState(() {});
              await OfflineStore.saveMessages(uid!, widget.conversation.id, messages);
            }
          },
        )
        .subscribe();

      try {
        await sb
            .from('messages')
            .update({'read_at': DateTime.now().toUtc().toIso8601String()})
            .eq('conversation_id', widget.conversation.id)
            .neq('sender_id', uid!)
            .isFilter('read_at', null);
      } catch (_) {
        // Read receipts are optional; don't break chat if the column is unavailable.
      }
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> send() async {
    final text = input.text.trim();
    if (text.isEmpty || uid == null) return;
    input.clear();

    final local = <String, dynamic>{
      'id': 'local_${DateTime.now().microsecondsSinceEpoch}',
      'conversation_id': widget.conversation.id,
      'sender_id': uid,
      'body': text,
      'message_type': 'text',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      '_pending': true,
    };

    setState(() => messages.add(local));
    await OfflineStore.saveMessages(uid!, widget.conversation.id, messages);

    try {
      final data = await sb
          .from('messages')
          .insert({
            'conversation_id': widget.conversation.id,
            'sender_id': uid,
            'body': text,
            'message_type': 'text',
            'delivered_at': DateTime.now().toUtc().toIso8601String(),
          })
          .select()
          .single();
      if (mounted) {
        setState(() {
          messages.removeWhere((item) => item['id'] == local['id']);
          messages.add(Map<String, dynamic>.from(data));
        });
      }
      await OfflineStore.saveMessages(uid!, widget.conversation.id, messages);
    } catch (_) {
      if (mounted) {
        setState(() {
          final index = messages.indexWhere((item) => item['id'] == local['id']);
          if (index >= 0) messages[index] = {...messages[index], '_offline': true};
        });
      }
    }
  }

  Future<String?> peer() async {
    if (uid == null) return null;
    final rows = await sb
        .from('conversation_members')
        .select('user_id')
        .eq('conversation_id', widget.conversation.id)
        .neq('user_id', uid!)
        .limit(1);
    return rows.isEmpty ? null : rows.first['user_id']?.toString();
  }

  Future<void> call(bool video) async {
    if (calling || uid == null) return;
    try {
      setState(() => calling = true);
      final peerId = await peer();
      if (peerId == null) throw Exception('Other participant not found');
      final data = await sb
          .from('calls')
          .insert({
            'caller_id': uid,
            'callee_id': peerId,
            'type': video ? 'video' : 'audio',
            'status': 'ringing',
          })
          .select()
          .single();
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CallPage(
              callId: data['id'].toString(),
              video: video,
              caller: true,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Call failed: $e')));
      }
    } finally {
      if (mounted) setState(() => calling = false);
    }
  }

  String time(dynamic value) {
    try {
      return TimeOfDay.fromDateTime(DateTime.parse(value.toString()).toLocal()).format(context);
    } catch (_) {
      return '';
    }
  }

  String day(dynamic value) {
    try {
      final date = DateTime.parse(value.toString()).toLocal();
      final now = DateTime.now();
      if (date.year == now.year && date.month == now.month && date.day == now.day) return 'Today';
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return '';
    }
  }

  Future<void> open(dynamic value) async {
    if (value == null || value.toString().isEmpty) return;
    await launchUrl(Uri.parse(value.toString()), mode: LaunchMode.externalApplication);
  }

  Widget bubble(Map<String, dynamic> message) {
    final mine = message['sender_id'] == uid;
    final type = '${message['message_type'] ?? 'text'}';
    final url = message['file_url'] ?? message['url'] ?? message['media_url'];
    final offline = message['_offline'] == true;
    final pending = message['_pending'] == true;
    final foreground = mine ? Colors.white : null;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        margin: EdgeInsets.only(left: mine ? 48 : 4, right: mine ? 4 : 48, bottom: 6),
        padding: const EdgeInsets.fromLTRB(13, 10, 11, 7),
        decoration: BoxDecoration(
          color: mine
              ? const Color(0xff2563eb)
              : (widget.dark ? const Color(0xff202938) : const Color(0xffe8edf5)),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 5),
            bottomRight: Radius.circular(mine ? 5 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (url != null && type.contains('image'))
              ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: GestureDetector(
                  onTap: () => open(url),
                  child: Image.network(
                    url.toString(),
                    height: 190,
                    width: 300,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(
                      height: 100,
                      child: Center(child: Icon(Icons.broken_image_outlined)),
                    ),
                  ),
                ),
              )
            else if (url != null)
              InkWell(
                onTap: () => open(url),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      type.contains('video')
                          ? Icons.play_circle_fill
                          : type.contains('audio')
                              ? Icons.headphones
                              : Icons.insert_drive_file,
                      color: foreground,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '${message['file_name'] ?? 'Open attachment'}',
                        style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            if ((message['body'] ?? '').toString().isNotEmpty && (url == null || type == 'text'))
              Text(
                '${message['body']}',
                style: TextStyle(color: foreground, fontSize: 16, height: 1.3),
              ),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  time(message['created_at']),
                  style: TextStyle(color: mine ? Colors.white70 : Colors.grey, fontSize: 10),
                ),
                if (mine)
                  Padding(
                    padding: const EdgeInsets.only(left: 5),
                    child: Icon(
                      pending
                          ? Icons.schedule
                          : offline
                              ? Icons.cloud_off
                              : Icons.done_all,
                      size: 14,
                      color: Colors.white70,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    if (channel != null) sb.removeChannel(channel!);
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.dark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xff2563eb));

    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: widget.dark ? const Color(0xff0f1117) : const Color(0xfff7f8fc),
        appBar: AppBar(
          titleSpacing: 0,
          title: Row(
            children: [
              CircleAvatar(
                radius: 21,
                child: Text(widget.conversation.name.isEmpty ? 'G' : widget.conversation.name[0].toUpperCase()),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.conversation.name, style: const TextStyle(fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis),
                    Text('Secure chat', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(onPressed: calling ? null : () => call(false), icon: const Icon(Icons.call_rounded)),
            IconButton(onPressed: calling ? null : () => call(true), icon: const Icon(Icons.videocam_rounded)),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'search') {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chat search coming next.')));
                }
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'search', child: Text('Search messages'))],
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : messages.isEmpty
                      ? const Center(child: Text('No messages yet'))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
                          itemCount: messages.length,
                          itemBuilder: (_, index) {
                            final message = messages[index];
                            final previous = index > 0 ? messages[index - 1] : null;
                            final showDay = previous == null || day(previous['created_at']) != day(message['created_at']);
                            return Column(
                              children: [
                                if (showDay)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    child: Chip(label: Text(day(message['created_at']), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                                  ),
                                bubble(message),
                              ],
                            );
                          },
                        ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(7, 5, 7, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Attachments require a configured chat-media bucket.'))),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                    Expanded(
                      child: TextField(
                        controller: input,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          hintText: 'Message',
                          prefixIcon: const Icon(Icons.emoji_emotions_outlined),
                          suffixIcon: IconButton(onPressed: () => input.clear(), icon: const Icon(Icons.close, size: 18)),
                          filled: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(26), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: input,
                      builder: (_, value, __) {
                        final hasText = value.text.trim().isNotEmpty;
                        return FloatingActionButton.small(
                          onPressed: hasText ? send : null,
                          child: Icon(hasText ? Icons.send_rounded : Icons.mic_rounded),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
