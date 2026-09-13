import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'chat_page.dart';
import 'ai_page.dart';
import 'call_history_page.dart';
import 'status_page.dart';
import 'community_page.dart';

class Conversation {
  final String id;
  final String name;
  final String message;
  final String time;
  Conversation({required this.id, required this.name, required this.message, required this.time});
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final sb = Supabase.instance.client;
  List<Conversation> chats = [];
  bool loading = true;
  bool dark = false;
  String query = '';

  @override
  void initState() { super.initState(); refresh(); }

  String clock(dynamic value) {
    if (value == null) return '';
    try { return TimeOfDay.fromDateTime(DateTime.parse(value.toString()).toLocal()).format(context); } catch (_) { return ''; }
  }

  Future<void> refresh() async {
    final user = sb.auth.currentUser;
    if (user == null) return;
    if (mounted) setState(() => loading = true);
    try {
      final memberships = await sb.from('conversation_members').select('conversation_id').eq('user_id', user.id);
      final result = <Conversation>[];
      for (final row in memberships) {
        final id = row['conversation_id'];
        final c = await sb.from('conversations').select('id,title,is_group').eq('id', id).maybeSingle();
        if (c == null) continue;
        var name = c['is_group'] == true ? '${c['title'] ?? 'Group'}' : 'GG User';
        if (c['is_group'] != true) {
          final others = await sb.from('conversation_members').select('user_id').eq('conversation_id', id).neq('user_id', user.id).limit(1);
          if (others.isNotEmpty) {
            final p = await sb.from('profiles').select('display_name').eq('id', others.first['user_id']).maybeSingle();
            name = '${p?['display_name'] ?? 'GG User'}';
          }
        }
        final last = await sb.from('messages').select('body,created_at').eq('conversation_id', id).order('created_at', ascending: false).limit(1).maybeSingle();
        result.add(Conversation(id: '$id', name: name, message: '${last?['body'] ?? 'No messages yet'}', time: clock(last?['created_at'])));
      }
      if (mounted) setState(() => chats = result);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not refresh chats: $e')));
    } finally { if (mounted) setState(() => loading = false); }
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
    await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Find a GG user'),
      content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: 'Name or username')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
        FilledButton(onPressed: () async {
          final term = controller.text.trim();
          if (term.isEmpty) return;
          try {
            final me = sb.auth.currentUser!.id;
            final users = await sb.from('profiles').select('id,display_name,username').neq('id', me).or('display_name.ilike.%$term%,username.ilike.%$term%').limit(20);
            if (!mounted) return;
            Navigator.pop(dialogContext);
            if (users.isEmpty) { snack('No users found.'); return; }
            final selected = await showDialog<dynamic>(context: context, builder: (selectContext) => SimpleDialog(
              title: const Text('Select user'),
              children: [for (final user in users) SimpleDialogOption(onPressed: () => Navigator.pop(selectContext, user), child: Text('${user['display_name'] ?? 'GG User'}'))],
            ));
            if (selected == null || !mounted) return;
            final id = await createDirect('${selected['id']}');
            if (!mounted) return;
            await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(conversation: Conversation(id: id, name: '${selected['display_name'] ?? 'GG User'}', message: '', time: ''), dark: dark)));
            refresh();
          } catch (e) { snack('New chat failed: $e'); }
        }, child: const Text('Search')),
      ],
    ));
    controller.dispose();
  }

  void snack(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final filtered = chats.where((c) => c.name.toLowerCase().contains(query.toLowerCase()) || c.message.toLowerCase().contains(query.toLowerCase())).toList();
    return Theme(data: dark ? ThemeData.dark(useMaterial3: true) : ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xff2563eb)), child: Scaffold(
      appBar: AppBar(title: const Text('GG Messenger', style: TextStyle(fontWeight: FontWeight.w900)), actions: [
        IconButton(tooltip: 'Communities', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CommunityPage())), icon: const Icon(Icons.groups_outlined)),
        IconButton(tooltip: 'Calls', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CallHistoryPage())), icon: const Icon(Icons.call_outlined)),
        IconButton(tooltip: 'Status', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StatusPage())), icon: const Icon(Icons.camera_alt_outlined)),
        IconButton(tooltip: 'Theme', onPressed: () => setState(() => dark = !dark), icon: Icon(dark ? Icons.light_mode : Icons.dark_mode)),
        IconButton(tooltip: 'New chat', onPressed: newChat, icon: const Icon(Icons.add)),
      ]),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: TextField(onChanged: (v) => setState(() => query = v), decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: 'Search conversations', filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16))))),
        Expanded(child: loading && chats.isEmpty ? const Center(child: CircularProgressIndicator()) : filtered.isEmpty ? Center(child: FilledButton.icon(onPressed: newChat, icon: const Icon(Icons.add), label: const Text('New conversation'))) : ListView.builder(
          itemCount: filtered.length,
          itemBuilder: (_, i) { final chat = filtered[i]; return ListTile(
            leading: CircleAvatar(child: Text(chat.name.isEmpty ? 'G' : chat.name[0].toUpperCase())),
            title: Text(chat.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(chat.message, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Text(chat.time, style: const TextStyle(fontSize: 11)),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(conversation: chat, dark: dark))).then((_) => refresh()),
          ); },
        )),
      ]),
      floatingActionButton: FloatingActionButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AIPage())), child: const Icon(Icons.auto_awesome)),
    ));
  }
}
