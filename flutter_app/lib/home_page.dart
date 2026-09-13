import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'ai_page.dart';
import 'call_history_page.dart';
import 'call_page.dart';
import 'chat_page.dart';
import 'community_page.dart';
import 'offline_store.dart';
import 'services/calls_repository.dart';
import 'status_page.dart';

class Conversation {
  final String id, name, message, time;
  Conversation({required this.id, required this.name, required this.message, required this.time});
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final sb = Supabase.instance.client;
  final Set<String> shownCalls = {};
  List<Conversation> chats = [];
  String query = '';
  bool dark = false, loading = true;
  RealtimeChannel? incomingChannel;
  StreamSubscription<List<ConnectivityResult>>? connectivity;
  Timer? periodic;

  @override
  void initState() {
    super.initState();
    refreshAndFlush();
    listenForIncomingCalls();
    connectivity = Connectivity().onConnectivityChanged.listen((_) => refreshAndFlush());
    periodic = Timer.periodic(const Duration(seconds: 30), (_) => refreshAndFlush());
  }

  String clock(dynamic value) {
    if (value == null) return '';
    try { return TimeOfDay.fromDateTime(DateTime.parse(value.toString()).toLocal()).format(context); } catch (_) { return ''; }
  }

  Future<void> refreshAndFlush() async {
    await flushOutbox();
    await refresh();
  }

  Future<void> flushOutbox() async {
    final user = sb.auth.currentUser;
    if (user == null) return;
    final items = await OfflineStore.loadOutbox(user.id);
    for (final item in items) {
      try {
        await sb.from('messages').insert({'conversation_id': item['conversation_id'], 'sender_id': user.id, 'body': item['body'], 'message_type': 'text', 'delivered_at': DateTime.now().toUtc().toIso8601String()});
        await OfflineStore.removeOutbox(user.id, '${item['local_id']}');
      } catch (_) {}
    }
  }

  Future<void> refresh() async {
    final user = sb.auth.currentUser;
    if (user == null) return;
    if (mounted) setState(() => loading = chats.isEmpty);
    try {
      final cached = await OfflineStore.loadHome(user.id);
      if (cached.isNotEmpty && mounted) {
        setState(() {
          chats = cached.map((x) => Conversation(id: '${x['id']}', name: '${x['name'] ?? 'GG User'}', message: '${x['message'] ?? ''}', time: '${x['time'] ?? ''}')).toList();
        });
      }
      final memberships = await sb.from('conversation_members').select('conversation_id').eq('user_id', user.id);
      final result = <Conversation>[];
      for (final membership in memberships) {
        final id = membership['conversation_id'];
        final conversation = await sb.from('conversations').select('id,title,is_group').eq('id', id).maybeSingle();
        if (conversation == null) continue;
        String name = conversation['is_group'] == true ? '${conversation['title'] ?? 'Group'}' : 'GG User';
        if (conversation['is_group'] != true) {
          final others = await sb.from('conversation_members').select('user_id').eq('conversation_id', id).neq('user_id', user.id).limit(1);
          if (others.isNotEmpty) {
            final profile = await sb.from('profiles').select('display_name').eq('id', others.first['user_id']).maybeSingle();
            name = '${profile?['display_name'] ?? 'GG User'}';
          }
        }
        final last = await sb.from('messages').select('body,created_at').eq('conversation_id', id).order('created_at', ascending: false).limit(1).maybeSingle();
        result.add(Conversation(id: '$id', name: name, message: '${last?['body'] ?? 'No messages yet'}', time: clock(last?['created_at'])));
      }
      if (mounted) setState(() => chats = result);
      await OfflineStore.saveHome(user.id, result.map((c) => {'id': c.id, 'name': c.name, 'message': c.message, 'time': c.time}).toList());
    } catch (_) {
      // Cached conversations remain visible offline.
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void snack(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  void listenForIncomingCalls() {
    final user = sb.auth.currentUser;
    if (user == null) return;
    incomingChannel = CallsRepository(sb).subscribeToIncoming(user.id, showIncomingCall);
  }

  Future<void> showIncomingCall(CallRecord call) async {
    if (!mounted || call.status != 'ringing' || shownCalls.contains(call.id)) return;
    shownCalls.add(call.id);
    String name = 'GG User';
    try {
      final profile = await sb.from('profiles').select('display_name').eq('id', call.callerId).maybeSingle();
      name = '${profile?['display_name'] ?? 'GG User'}';
    } catch (_) {}
    if (!mounted) return;
    final answer = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(call.type == 'video' ? 'Incoming video call' : 'Incoming voice call'),
        content: Text('$name is calling you.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Decline')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Answer')),
        ],
      ),
    );
    if (!mounted) return;
    try {
      if (answer == true) {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => CallPage(callId: call.id, video: call.type == 'video', caller: false)));
      } else {
        await CallsRepository(sb).setStatus(call.id, 'rejected');
      }
    } catch (e) { snack('Call error: $e'); }
  }

  Future<String> createDirect(String other) async {
    final me = sb.auth.currentUser!.id;
    final mine = await sb.from('conversation_members').select('conversation_id').eq('user_id', me);
    for (final row in mine) {
      final member = await sb.from('conversation_members').select('user_id').eq('conversation_id', row['conversation_id']).eq('user_id', other).maybeSingle();
      if (member != null) {
        final c = await sb.from('conversations').select('id').eq('id', row['conversation_id']).eq('is_group', false).maybeSingle();
        if (c != null) return '${c['id']}';
      }
    }
    final c = await sb.from('conversations').insert({'is_group': false}).select('id').single();
    await sb.from('conversation_members').insert([
      {'conversation_id': c['id'], 'user_id': me},
      {'conversation_id': c['id'], 'user_id': other},
    ]);
    return '${c['id']}';
  }

  Future<void> newChat() async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Find a GG user'),
        content: TextField(controller: controller, decoration: const InputDecoration(hintText: 'Name or username')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final term = controller.text.trim();
              if (term.isEmpty) return;
              try {
                final me = sb.auth.currentUser!.id;
                final users = await sb.from('profiles').select('id,display_name,username').neq('id', me).or('display_name.ilike.%$term%,username.ilike.%$term%').limit(20);
                if (!context.mounted) return;
                Navigator.pop(dialogContext);
                if (users.isEmpty) { snack('No users found.'); return; }
                final selected = await showDialog<dynamic>(
                  context: context,
                  builder: (selectContext) => SimpleDialog(
                    title: const Text('Select user'),
                    children: [
                      for (final user in users)
                        SimpleDialogOption(onPressed: () => Navigator.pop(selectContext, user), child: Text('${user['display_name'] ?? 'GG User'}')),
                    ],
                  ),
                );
                if (selected != null && context.mounted) {
                  final id = await createDirect('${selected['id']}');
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(conversation: Conversation(id: id, name: '${selected['display_name'] ?? 'GG User'}', message: '', time: ''), dark: dark)));
                  refresh();
                }
              } catch (e) { snack('$e'); }
            },
            child: const Text('Search'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  void profile() {
    final user = sb.auth.currentUser;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(child: Wrap(children: [
        ListTile(leading: const Icon(Icons.person), title: const Text('View profile'), subtitle: Text(user?.email ?? 'GG user')),
        ListTile(leading: const Icon(Icons.dark_mode), title: const Text('Theme'), trailing: Switch(value: dark, onChanged: (value) { setState(() => dark = value); Navigator.pop(sheetContext); })),
        ListTile(leading: const Icon(Icons.settings), title: const Text('Settings'), onTap: () => Navigator.pop(sheetContext)),
        ListTile(leading: const Icon(Icons.help_outline), title: const Text('Help & support'), onTap: () => Navigator.pop(sheetContext)),
      ])),
    );
  }

  @override
  void dispose() {
    connectivity?.cancel();
    periodic?.cancel();
    if (incomingChannel != null) sb.removeChannel(incomingChannel!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = chats.where((c) => c.name.toLowerCase().contains(query.toLowerCase())).toList();
    final theme = dark ? ThemeData.dark(useMaterial3: true) : ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xff00a884));
    return Theme(data: theme, child: Scaffold(
      appBar: AppBar(
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('GG', style: TextStyle(fontWeight: FontWeight.w900)), Text('Messenger', style: TextStyle(fontSize: 12))]),
        actions: [
          IconButton(tooltip: 'Communities', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CommunityPage())), icon: const Icon(Icons.groups_outlined)),
          IconButton(tooltip: 'Calls', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CallHistoryPage())), icon: const Icon(Icons.call_outlined)),
          IconButton(tooltip: 'Status', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StatusPage())), icon: const Icon(Icons.camera_alt_outlined)),
          IconButton(onPressed: profile, icon: const Icon(Icons.person_outline)),
          IconButton(onPressed: newChat, icon: const Icon(Icons.add)),
        ],
      ),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: TextField(onChanged: (value) => setState(() => query = value), decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: 'Search conversations', filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16))))),
        Expanded(child: loading && chats.isEmpty ? const Center(child: CircularProgressIndicator()) : filtered.isEmpty ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.chat_bubble_outline, size: 54), const SizedBox(height: 12), const Text('No conversations yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), FilledButton(onPressed: newChat, child: const Text('New conversation'))])) : ListView.builder(itemCount: filtered.length, itemBuilder: (_, index) {
          final chat = filtered[index];
          return ListTile(leading: CircleAvatar(child: Text(chat.name.isEmpty ? 'G' : chat.name[0].toUpperCase())), title: Text(chat.name, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(chat.message, maxLines: 1, overflow: TextOverflow.ellipsis), trailing: Text(chat.time, style: const TextStyle(fontSize: 11)), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(conversation: chat, dark: dark))).then((_) => refresh()));
        })),
      ]),
      floatingActionButton: FloatingActionButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AIPage())), child: const Icon(Icons.auto_awesome)),
    ));
  }
}
