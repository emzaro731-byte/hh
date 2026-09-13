import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'chat_page.dart';
import 'ai_page.dart';
import 'call_page.dart';
import 'call_history_page.dart';
import 'status_page.dart';
import 'community_page.dart';
import 'services/calls_repository.dart';
import 'offline_store.dart';

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
  StreamSubscription<List<ConnectivityResult>>? connectivity;
  Timer? periodic;
  final Set<String> shownCalls = {};

  @override
  void initState() {
    super.initState();
    refresh();
    _listenForIncomingCalls();
    connectivity = Connectivity().onConnectivityChanged.listen((_) => refreshAndFlush());
    periodic = Timer.periodic(const Duration(seconds: 30), (_) => refreshAndFlush());
  }

  String clock(dynamic value) {
    if (value == null) return '';
    try { return TimeOfDay.fromDateTime(DateTime.parse(value.toString()).toLocal()).format(context); } catch (_) { return ''; }
  }

  Future<void> refreshAndFlush() async {
    await _flushOutbox();
    await refresh();
  }

  Future<void> _flushOutbox() async {
    final u = sb.auth.currentUser;
    if (u == null) return;
    final items = await OfflineStore.loadOutbox(u.id);
    for (final item in List<Map<String, dynamic>>.from(items)) {
      try {
        await sb.from('messages').insert({'conversation_id': item['conversation_id'], 'sender_id': u.id, 'body': item['body'], 'message_type': 'text', 'delivered_at': DateTime.now().toUtc().toIso8601String()});
        await OfflineStore.removeOutbox(u.id, item['local_id'].toString());
      } catch (_) {}
    }
  }

  Future<void> refresh() async {
    final u = sb.auth.currentUser;
    if (u == null) return;
    if (mounted) setState(() => loading = true);
    try {
      final cached = await OfflineStore.loadHome(u.id);
      if (cached.isNotEmpty && mounted) {
        setState(() {
          chats = cached.map((x) => Conversation(id: '${x['id']}', name: '${x['name'] ?? 'GG User'}', message: '${x['message'] ?? ''}', time: '${x['time'] ?? ''}')).toList();
        });
      }
      final memberships = await sb.from('conversation_members').select('conversation_id').eq('user_id', u.id);
      final result = <Conversation>[];
      for (final row in memberships) {
        final id = row['conversation_id'];
        final c = await sb.from('conversations').select('id,title,is_group').eq('id', id).maybeSingle();
        if (c == null) continue;
        String name = c['is_group'] == true ? (c['title'] ?? 'Group').toString() : 'GG User';
        if (c['is_group'] != true) {
          final others = await sb.from('conversation_members').select('user_id').eq('conversation_id', id).neq('user_id', u.id).limit(1);
          if (others.isNotEmpty) {
            final p = await sb.from('profiles').select('display_name').eq('id', others.first['user_id']).maybeSingle();
            name = '${p?['display_name'] ?? 'GG User'}';
          }
        }
        final last = await sb.from('messages').select('body,created_at').eq('conversation_id', id).order('created_at', ascending: false).limit(1).maybeSingle();
        result.add(Conversation(id: '$id', name: name, message: '${last?['body'] ?? 'No messages yet'}', time: clock(last?['created_at'])));
      }
      if (mounted) setState(() => chats = result);
      await OfflineStore.saveHome(u.id, result.map((x) => {'id': x.id, 'name': x.name, 'message': x.message, 'time': x.time}).toList());
    } catch (_) {
      // Keep cached conversations visible while offline.
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void snack(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  void _listenForIncomingCalls() {
    final u = sb.auth.currentUser;
    if (u == null) return;
    incomingChannel = CallsRepository(sb).subscribeToIncoming(u.id, _showIncomingCall);
  }

  Future<void> _showIncomingCall(CallRecord call) async {
    if (!mounted || call.status != 'ringing' || shownCalls.contains(call.id)) return;
    shownCalls.add(call.id);
    String name = 'GG User';
    try {
      final p = await sb.from('profiles').select('display_name').eq('id', call.callerId).maybeSingle();
      name = '${p?['display_name'] ?? 'GG User'}';
    } catch (_) {}
    if (!mounted) return;
    final answer = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(call.type == 'video' ? 'Incoming video call' : 'Incoming voice call'),
        content: Text('$name is calling you.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Decline')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Answer')),
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
    await sb.from('conversation_members').insert([{'conversation_id': c['id'], 'user_id': me}, {'conversation_id': c['id'], 'user_id': other}]);
    return '${c['id']}';
  }

  Future<void> newChat() async {
    final ctl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Find a GG user'),
        content: TextField(controller: ctl, decoration: const InputDecoration(hintText: 'Name or username')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              try {
                final term = ctl.text.trim();
                if (term.isEmpty) return;
                final me = sb.auth.currentUser!.id;
                final users = await sb.from('profiles').select('id,display_name,username').neq('id', me).or('display_name.ilike.%$term%,username.ilike.%$term%').limit(20);
                if (!context.mounted) return;
                Navigator.pop(context);
                if (users.isEmpty) { snack('No users found.'); return; }
                final selected = await showDialog<dynamic>(
                  context: context,
                  builder: (_) => SimpleDialog(
                    title: const Text('Select user'),
                    children: [for (final u in users) SimpleDialogOption(onPressed: () => Navigator.pop(context, u), child: Text('${u['display_name'] ?? 'GG User'}'))],
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
    ctl.dispose();
  }

  void profile() {
    final u = sb.auth.currentUser;
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(children: [
          ListTile(leading: const Icon(Icons.person), title: const Text('View profile'), subtitle: Text(u?.email ?? 'GG user')),
          ListTile(leading: const Icon(Icons.dark_mode), title: const Text('Theme'), trailing: Switch(value: dark, onChanged: (v) { setState(() => dark = v); Navigator.pop(context); })),
          ListTile(leading: const Icon(Icons.settings), title: const Text('Settings'), onTap: () => Navigator.pop(context)),
          ListTile(leading: const Icon(Icons.help_outline), title: const Text('Help & support'), onTap: () => Navigator.pop(context)),
        ]),
      ),
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
    final list = chats.where((c) => c.name.toLowerCase().contains(query.toLowerCase())).toList();
    final theme = dark ? ThemeData.dark(useMaterial3: true) : ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xff00a884));
    return Theme(
      data: theme,
      child: Scaffold(
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
          Padding(padding: const EdgeInsets.all(12), child: TextField(onChanged: (v) => setState(() => query = v), decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: 'Search conversations', filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16))))),
          Expanded(
            child: loading && chats.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                    ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.chat_bubble_outline, size: 54), const SizedBox(height: 12), const Text('No conversations yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), FilledButton(onPressed: newChat, child: const Text('New conversation'))]))
                    : ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final chat = list[i];
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
        ]),
        floatingActionButton: FloatingActionButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AIPage())), child: const Icon(Icons.auto_awesome)),
      ),
    );
  }
}
