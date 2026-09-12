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
  @override State<OfflineHomePage> createState() => _OfflineHomePageState();
}

class _OfflineHomePageState extends State<OfflineHomePage> {
  final sb = Supabase.instance.client;
  List<Conversation> chats = [];
  String query = '';
  bool loading = true, dark = false;
  RealtimeChannel? incoming;
  final Set<String> shown = {};

  @override void initState() { super.initState(); _start(); }

  Future<void> _start() async {
    final u = sb.auth.currentUser;
    if (u == null) { if (mounted) setState(() => loading = false); return; }
    final cached = await OfflineStore.loadHome(u.id);
    if (mounted && cached.isNotEmpty) {
      setState(() {
        chats = cached.map((x) => Conversation(id: '${x['id']}', name: '${x['name'] ?? 'GG User'}', message: '${x['message'] ?? ''}', time: '${x['time'] ?? ''}')).toList();
        loading = false;
      });
    }
    await refresh(silent: cached.isNotEmpty);
    _listenCalls();
  }

  String clock(dynamic v) { if (v == null) return ''; try { return TimeOfDay.fromDateTime(DateTime.parse(v.toString()).toLocal()).format(context); } catch (_) { return ''; } }

  Future<void> refresh({bool silent = false}) async {
    final u = sb.auth.currentUser;
    if (u == null) return;
    if (!silent && mounted) setState(() => loading = true);
    try {
      final mem = await sb.from('conversation_members').select('conversation_id').eq('user_id', u.id);
      final out = <Conversation>[];
      for (final row in mem) {
        final id = row['conversation_id'];
        final c = await sb.from('conversations').select('id,title,is_group').eq('id', id).maybeSingle();
        if (c == null) continue;
        final others = await sb.from('conversation_members').select('user_id').eq('conversation_id', id).neq('user_id', u.id).limit(1);
        String name = c['is_group'] == true ? '${c['title'] ?? 'Group'}' : 'GG User';
        if (others.isNotEmpty) {
          final p = await sb.from('profiles').select('display_name').eq('id', others.first['user_id']).maybeSingle();
          name = '${p?['display_name'] ?? 'GG User'}';
        }
        final last = await sb.from('messages').select('body,created_at').eq('conversation_id', id).order('created_at', ascending: false).limit(1).maybeSingle();
        out.add(Conversation(id: '$id', name: name, message: '${last?['body'] ?? 'No messages yet'}', time: clock(last?['created_at'])));
      }
      await OfflineStore.saveHome(u.id, [for (final x in out) {'id': x.id, 'name': x.name, 'message': x.message, 'time': x.time}]);
      if (mounted) setState(() { chats = out; loading = false; });
    } catch (_) { if (mounted) setState(() => loading = false); }
  }

  void _listenCalls() {
    final u = sb.auth.currentUser; if (u == null) return;
    incoming = CallsRepository(sb).subscribeToIncoming(u.id, (call) async {
      if (!mounted || call.status != 'ringing' || shown.contains(call.id)) return;
      shown.add(call.id);
      final video = call.type == 'video';
      final answer = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => AlertDialog(
        title: Text(video ? 'Incoming video call' : 'Incoming voice call'),
        content: const Text('Someone is calling you.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Decline')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Answer'))],
      ));
      if (!mounted) return;
      if (answer == true) await Navigator.push(context, MaterialPageRoute(builder: (_) => CallPage(callId: call.id, video: video, caller: false)));
      else await CallsRepository(sb).setStatus(call.id, 'rejected');
    });
  }

  Future<void> newChat() async {
    final q = TextEditingController();
    await showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('New chat'),
      content: TextField(controller: q, decoration: const InputDecoration(hintText: 'Name or username')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () async {
          final term = q.text.trim(); if (term.isEmpty) return;
          try {
            final me = sb.auth.currentUser!.id;
            final users = await sb.from('profiles').select('id,display_name,username').neq('id', me).or('display_name.ilike.%$term%,username.ilike.%$term%').limit(20);
            if (!context.mounted) return;
            Navigator.pop(context);
            if (users.isEmpty) { _snack('No users found.'); return; }
            final x = await showDialog<dynamic>(context: context, builder: (_) => SimpleDialog(title: const Text('Select user'), children: [for (final p in users) SimpleDialogOption(onPressed: () => Navigator.pop(context, p), child: Text('${p['display_name'] ?? 'GG User'}'))]));
            if (x != null) {
              final id = await _createDirect('${x['id']}');
              if (context.mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => OfflineChatPage(conversation: Conversation(id: id, name: '${x['display_name'] ?? 'GG User'}', message: '', time: ''), dark: dark)));
              if (context.mounted) refresh();
            }
          } catch (e) { _snack(e.toString()); }
        }, child: const Text('Search')),
      ],
    ));
    q.dispose();
  }

  Future<String> _createDirect(String other) async {
    final me = sb.auth.currentUser!.id;
    final mine = await sb.from('conversation_members').select('conversation_id').eq('user_id', me);
    for (final r in mine) {
      final x = await sb.from('conversation_members').select('user_id').eq('conversation_id', r['conversation_id']).eq('user_id', other).maybeSingle();
      if (x != null) {
        final c = await sb.from('conversations').select('id').eq('id', r['conversation_id']).eq('is_group', false).maybeSingle();
        if (c != null) return '${c['id']}';
      }
    }
    final c = await sb.from('conversations').insert({'is_group': false}).select('id').single();
    await sb.from('conversation_members').insert([{'conversation_id': c['id'], 'user_id': me}, {'conversation_id': c['id'], 'user_id': other}]);
    return '${c['id']}';
  }

  void _snack(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  @override void dispose() { if (incoming != null) sb.removeChannel(incoming!); super.dispose(); }

  @override Widget build(BuildContext context) {
    final list = chats.where((x) => x.name.toLowerCase().contains(query.toLowerCase())).toList();
    return Theme(data: dark ? ThemeData.dark(useMaterial3: true) : ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xff2563eb)), child: Scaffold(
      appBar: AppBar(title: const Text('GG Messenger', style: TextStyle(fontWeight: FontWeight.w800)), actions: [IconButton(onPressed: () => setState(() => dark = !dark), icon: Icon(dark ? Icons.light_mode : Icons.dark_mode)), IconButton(onPressed: newChat, icon: const Icon(Icons.add))]),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 12), child: TextField(onChanged: (v) => setState(() => query = v), decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: 'Search chats', filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(24))))),
        Expanded(child: loading ? const Center(child: CircularProgressIndicator()) : list.isEmpty ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.chat_bubble_outline, size: 56), const SizedBox(height: 12), const Text('No chats yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), FilledButton(onPressed: newChat, child: const Text('Start a chat'))])) : ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 84),
          itemBuilder: (_, i) { final x = list[i]; return ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), leading: CircleAvatar(radius: 28, child: Text(x.name.isEmpty ? 'G' : x.name[0].toUpperCase())), title: Text(x.name, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(x.message, maxLines: 1, overflow: TextOverflow.ellipsis), trailing: Text(x.time, style: const TextStyle(fontSize: 11)), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OfflineChatPage(conversation: x, dark: dark))).then((_) => refresh()); }
        )),
      ]),
      floatingActionButton: FloatingActionButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AIPage())), child: const Icon(Icons.auto_awesome)),
    ));
  }
}
