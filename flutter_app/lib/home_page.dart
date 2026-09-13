import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'chat_page.dart';
import 'ai_page.dart';
import 'call_page.dart';
import 'call_history_page.dart';
import 'status_page.dart';
import 'services/calls_repository.dart';

class Conversation {
  final String id, name, message, time;
  Conversation({required this.id, required this.name, required this.message, required this.time});
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool dark = false, loading = true;
  String query = '';
  List<Conversation> chats = [];
  final sb = Supabase.instance.client;
  RealtimeChannel? incomingChannel;
  final Set<String> shownCalls = {};

  @override
  void initState() {
    super.initState();
    refresh();
    _listenForIncomingCalls();
  }

  String clock(dynamic value) {
    if (value == null) return '';
    final date = DateTime.parse(value.toString()).toLocal();
    return TimeOfDay.fromDateTime(date).format(context);
  }

  Future<void> refresh() async {
    if (mounted) setState(() => loading = true);
    try {
      final user = sb.auth.currentUser;
      if (user == null) return;
      final memberships = await sb.from('conversation_members').select('conversation_id').eq('user_id', user.id);
      final result = <Conversation>[];
      for (final row in memberships) {
        final id = row['conversation_id'];
        final conversation = await sb.from('conversations').select('id,title,is_group').eq('id', id).maybeSingle();
        if (conversation == null) continue;
        final others = await sb.from('conversation_members').select('user_id').eq('conversation_id', id).neq('user_id', user.id).limit(1);
        String name = conversation['is_group'] == true ? (conversation['title'] ?? 'Group').toString() : 'GG User';
        if (others.isNotEmpty) {
          final profile = await sb.from('profiles').select('display_name').eq('id', others.first['user_id']).maybeSingle();
          name = (profile?['display_name'] ?? 'GG User').toString();
        }
        final last = await sb.from('messages').select('body,created_at').eq('conversation_id', id).order('created_at', ascending: false).limit(1).maybeSingle();
        result.add(Conversation(id: id.toString(), name: name, message: (last?['body'] ?? 'No messages yet').toString(), time: clock(last?['created_at'])));
      }
      if (mounted) setState(() => chats = result);
    } catch (e) {
      snack(e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void snack(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  void _listenForIncomingCalls() {
    final user = sb.auth.currentUser;
    if (user == null) return;
    incomingChannel = CallsRepository(sb).subscribeToIncoming(user.id, _showIncomingCall);
  }

  Future<void> _showIncomingCall(CallRecord call) async {
    if (!mounted || call.status != 'ringing' || shownCalls.contains(call.id)) return;
    shownCalls.add(call.id);
    String callerName = 'GG User';
    try {
      final profile = await sb.from('profiles').select('display_name').eq('id', call.callerId).maybeSingle();
      callerName = (profile?['display_name'] ?? 'GG User').toString();
    } catch (_) {}
    if (!mounted) return;
    final video = call.type == 'video';
    final answer = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(video ? 'Incoming video call' : 'Incoming voice call'),
        content: Text('$callerName is calling you.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Decline')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Answer')),
        ],
      ),
    );
    if (!mounted) return;
    try {
      if (answer == true) {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => CallPage(callId: call.id, video: video, caller: false)));
      } else {
        await CallsRepository(sb).setStatus(call.id, 'rejected');
      }
    } catch (e) {
      snack('Call error: $e');
    }
  }

  Future<String> createDirect(String other) async {
    final me = sb.auth.currentUser!.id;
    final mine = await sb.from('conversation_members').select('conversation_id').eq('user_id', me);
    for (final row in mine) {
      final member = await sb.from('conversation_members').select('user_id').eq('conversation_id', row['conversation_id']).eq('user_id', other).maybeSingle();
      if (member != null) {
        final conversation = await sb.from('conversations').select('id').eq('id', row['conversation_id']).eq('is_group', false).maybeSingle();
        if (conversation != null) return conversation['id'].toString();
      }
    }
    final conversation = await sb.from('conversations').insert({'is_group': false}).select('id').single();
    await sb.from('conversation_members').insert([
      {'conversation_id': conversation['id'], 'user_id': me},
      {'conversation_id': conversation['id'], 'user_id': other},
    ]);
    return conversation['id'].toString();
  }

  Future<void> newChat() async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Find a GG user'),
        content: TextField(controller: controller, decoration: const InputDecoration(hintText: 'Name or username')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final term = controller.text.trim();
              if (term.isEmpty) return;
              try {
                final me = sb.auth.currentUser!.id;
                final users = await sb.from('profiles').select('id,display_name,username').neq('id', me).or('display_name.ilike.%$term%,username.ilike.%$term%').limit(20);
                if (!context.mounted) return;
                Navigator.pop(context);
                if (users.isEmpty) {
                  snack('No users found.');
                  return;
                }
                final selected = await showDialog<dynamic>(
                  context: context,
                  builder: (_) => SimpleDialog(
                    title: const Text('Select user'),
                    children: [
                      for (final user in users)
                        SimpleDialogOption(
                          onPressed: () => Navigator.pop(context, user),
                          child: Text((user['display_name'] ?? 'GG User').toString()),
                        ),
                    ],
                  ),
                );
                if (selected != null && context.mounted) {
                  final id = await createDirect(selected['id'].toString());
                  if (!context.mounted) return;
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(conversation: Conversation(id: id, name: (selected['display_name'] ?? 'GG User').toString(), message: '', time: ''), dark: dark)));
                  if (mounted) refresh();
                }
              } catch (e) {
                snack(e.toString());
              }
            },
            child: const Text('Search'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  @override
  void dispose() {
    if (incomingChannel != null) sb.removeChannel(incomingChannel!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = chats.where((chat) => chat.name.toLowerCase().contains(query.toLowerCase())).toList();
    final theme = dark
        ? ThemeData.dark(useMaterial3: true).copyWith(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff2563eb), brightness: Brightness.dark))
        : ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xff2563eb));
    return Theme(
      data: theme,
      child: Scaffold(
        appBar: AppBar(
          title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('GG', style: TextStyle(fontWeight: FontWeight.w900)), Text('Messenger', style: TextStyle(fontSize: 12))]),
          actions: [
            IconButton(tooltip: 'Calls', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CallHistoryPage())), icon: const Icon(Icons.call_outlined)),
            IconButton(tooltip: 'Status', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StatusPage())), icon: const Icon(Icons.camera_alt_outlined)),
            IconButton(onPressed: () => setState(() => dark = !dark), icon: Icon(dark ? Icons.light_mode : Icons.dark_mode)),
            IconButton(onPressed: newChat, icon: const Icon(Icons.add)),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                onChanged: (value) => setState(() => query = value),
                decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: 'Search conversations', filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16))),
              ),
            ),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : list.isEmpty
                      ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.chat_bubble_outline, size: 54), const SizedBox(height: 12), const Text('No conversations yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), FilledButton(onPressed: newChat, child: const Text('New conversation'))]))
                      : ListView.builder(
                          itemCount: list.length,
                          itemBuilder: (_, index) {
                            final chat = list[index];
                            return ListTile(
                              leading: CircleAvatar(child: Text(chat.name.isEmpty ? 'G' : chat.name[0].toUpperCase())),
                              title: Text(chat.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text(chat.message, maxLines: 1, overflow: TextOverflow.ellipsis),
                              trailing: Text(chat.time, style: const TextStyle(fontSize: 11)),
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(conversation: chat, dark: dark))).then((_) => refresh()),
                            );
                          },
                        ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AIPage())), child: const Icon(Icons.auto_awesome)),
      ),
    );
  }
}
