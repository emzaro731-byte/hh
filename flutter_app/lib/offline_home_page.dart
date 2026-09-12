import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_page.dart';
import 'offline_chat_page.dart';
import 'offline_store.dart';
import 'ai_page.dart';
import 'call_page.dart';
import 'services/calls_repository.dart';

class OfflineHomePage extends StatefulWidget {
  const OfflineHomePage({super.key});

  @override
  State<OfflineHomePage> createState() => _OfflineHomePageState();
}

class _OfflineHomePageState extends State<OfflineHomePage> {
  final sb = Supabase.instance.client;
  List<Conversation> chats = [];
  String query = '';
  bool loading = true;
  bool dark = false;
  RealtimeChannel? incoming;
  final Set<String> shown = {};

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final user = sb.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => loading = false);
      return;
    }

    final cached = await OfflineStore.loadHome(user.id);
    if (mounted && cached.isNotEmpty) {
      setState(() {
        chats = cached.map((x) => Conversation(
          id: '${x['id']}',
          name: '${x['name'] ?? 'GG User'}',
          message: '${x['message'] ?? ''}',
          time: '${x['time'] ?? ''}',
        )).toList();
        loading = false;
      });
    }

    await refresh(silent: cached.isNotEmpty);
    _listenCalls();
  }

  String clock(dynamic value) {
    if (value == null) return '';
    try {
      final date = DateTime.parse(value.toString()).toLocal();
      return TimeOfDay.fromDateTime(date).format(context);
    } catch (_) {
      return '';
    }
  }

  Future<void> refresh({bool silent = false}) async {
    final user = sb.auth.currentUser;
    if (user == null) return;
    if (!silent && mounted) setState(() => loading = true);

    try {
      final members = await sb.from('conversation_members')
          .select('conversation_id').eq('user_id', user.id);
      final result = <Conversation>[];

      for (final row in members) {
        final id = row['conversation_id'];
        final conversation = await sb.from('conversations')
            .select('id,title,is_group').eq('id', id).maybeSingle();
        if (conversation == null) continue;

        final others = await sb.from('conversation_members')
            .select('user_id').eq('conversation_id', id)
            .neq('user_id', user.id).limit(1);

        String name = conversation['is_group'] == true
            ? '${conversation['title'] ?? 'Group'}' : 'GG User';
        if (others.isNotEmpty) {
          final profile = await sb.from('profiles')
              .select('display_name').eq('id', others.first['user_id'])
              .maybeSingle();
          name = '${profile?['display_name'] ?? 'GG User'}';
        }

        final last = await sb.from('messages').select('body,created_at')
            .eq('conversation_id', id)
            .order('created_at', ascending: false).limit(1).maybeSingle();

        result.add(Conversation(
          id: '$id', name: name,
          message: '${last?['body'] ?? 'No messages yet'}',
          time: clock(last?['created_at']),
        ));
      }

      await OfflineStore.saveHome(user.id, [
        for (final chat in result)
          {'id': chat.id, 'name': chat.name, 'message': chat.message, 'time': chat.time},
      ]);

      if (mounted) setState(() { chats = result; loading = false; });
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  void _listenCalls() {
    final user = sb.auth.currentUser;
    if (user == null) return;

    incoming = CallsRepository(sb).subscribeToIncoming(user.id, (call) async {
      if (!mounted || call.status != 'ringing' || shown.contains(call.id)) return;
      shown.add(call.id);
      final video = call.type == 'video';

      final answer = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Text(video ? 'Incoming video call' : 'Incoming voice call'),
          content: const Text('Someone is calling you.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Decline'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Answer'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      if (answer == true) {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => CallPage(callId: call.id, video: video, caller: false),
        ));
      } else {
        await CallsRepository(sb).setStatus(call.id, 'rejected');
      }
    });
  }

  Future<void> newChat() async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New chat'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Name or username'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final term = controller.text.trim();
              if (term.isEmpty) return;
              try {
                final me = sb.auth.currentUser!.id;
                final users = await sb.from('profiles')
                    .select('id,display_name,username').neq('id', me)
                    .or('display_name.ilike.%$term%,username.ilike.%$term%')
                    .limit(20);
                if (!mounted) return;
                Navigator.of(dialogContext).pop();
                if (users.isEmpty) {
                  _snack('No users found.');
                  return;
                }

                final selected = await showDialog<dynamic>(
                  context: context,
                  builder: (selectContext) => SimpleDialog(
                    title: const Text('Select user'),
                    children: [
                      for (final profile in users)
                        SimpleDialogOption(
                          onPressed: () => Navigator.of(selectContext).pop(profile),
                          child: Text('${profile['display_name'] ?? 'GG User'}'),
                        ),
                    ],
                  ),
                );

                if (selected == null || !mounted) return;
                final conversationId = await _createDirect('${selected['id']}');
                if (!mounted) return;

                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => OfflineChatPage(
                    conversation: Conversation(
                      id: conversationId,
                      name: '${selected['display_name'] ?? 'GG User'}',
                      message: '',
                      time: '',
                    ),
                    dark: dark,
                  ),
                ));
                if (mounted) await refresh();
              } catch (error) {
                _snack(error.toString());
              }
            },
            child: const Text('Search'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<String> _createDirect(String other) async {
    final me = sb.auth.currentUser!.id;
    final mine = await sb.from('conversation_members')
        .select('conversation_id').eq('user_id', me);

    for (final row in mine) {
      final member = await sb.from('conversation_members')
          .select('user_id').eq('conversation_id', row['conversation_id'])
          .eq('user_id', other).maybeSingle();
      if (member != null) {
        final conversation = await sb.from('conversations')
            .select('id').eq('id', row['conversation_id'])
            .eq('is_group', false).maybeSingle();
        if (conversation != null) return '${conversation['id']}';
      }
    }

    final conversation = await sb.from('conversations')
        .insert({'is_group': false}).select('id').single();
    await sb.from('conversation_members').insert([
      {'conversation_id': conversation['id'], 'user_id': me},
      {'conversation_id': conversation['id'], 'user_id': other},
    ]);
    return '${conversation['id']}';
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    final channel = incoming;
    if (channel != null) sb.removeChannel(channel);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = chats.where((chat) =>
        chat.name.toLowerCase().contains(query.toLowerCase())).toList();

    return Theme(
      data: dark
          ? ThemeData.dark(useMaterial3: true)
          : ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xff2563eb)),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('GG Messenger', style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            IconButton(
              tooltip: 'Theme',
              onPressed: () => setState(() => dark = !dark),
              icon: Icon(dark ? Icons.light_mode : Icons.dark_mode),
            ),
            IconButton(
              tooltip: 'New chat',
              onPressed: newChat,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: TextField(
                onChanged: (value) => setState(() => query = value),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search chats',
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                ),
              ),
            ),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.chat_bubble_outline, size: 56),
                              const SizedBox(height: 12),
                              const Text('No chats yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              FilledButton(onPressed: newChat, child: const Text('Start a chat')),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, indent: 84),
                          itemBuilder: (_, index) {
                            final chat = filtered[index];
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              leading: CircleAvatar(
                                radius: 28,
                                child: Text(chat.name.isEmpty ? 'G' : chat.name[0].toUpperCase()),
                              ),
                              title: Text(chat.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text(chat.message, maxLines: 1, overflow: TextOverflow.ellipsis),
                              trailing: Text(chat.time, style: const TextStyle(fontSize: 11)),
                              onTap: () {
                                Navigator.of(context)
                                    .push(MaterialPageRoute(
                                      builder: (_) => OfflineChatPage(conversation: chat, dark: dark),
                                    ))
                                    .then((_) => refresh());
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          tooltip: 'AI Studio',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AIPage()),
          ),
          child: const Icon(Icons.auto_awesome),
        ),
      ),
    );
  }
}
