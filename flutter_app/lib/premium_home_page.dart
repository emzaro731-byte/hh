import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_page.dart';
import 'chat_page.dart';
import 'offline_store.dart';
import 'call_page.dart';
import 'services/calls_repository.dart';

class PremiumHomePage extends StatefulWidget {
  const PremiumHomePage({super.key});
  @override State<PremiumHomePage> createState() => _PremiumHomePageState();
}

class _PremiumHomePageState extends State<PremiumHomePage> {
  final sb = Supabase.instance.client;
  final search = TextEditingController();
  List<Conversation> chats = [];
  bool loading = true, dark = true;
  RealtimeChannel? incoming;
  final shown = <String>{};

  @override
  void initState() { super.initState(); _refresh(); _listenCalls(); }

  String clock(dynamic v) {
    if (v == null) return '';
    try { return TimeOfDay.fromDateTime(DateTime.parse('$v').toLocal()).format(context); } catch (_) { return ''; }
  }

  Future<void> _refresh() async {
    final user = sb.auth.currentUser;
    if (user == null) return;
    if (mounted) setState(() => loading = true);
    try {
      final members = await sb.from('conversation_members').select('conversation_id').eq('user_id', user.id);
      final result = <Conversation>[];
      for (final row in members) {
        final id = row['conversation_id'];
        final c = await sb.from('conversations').select('id,title,is_group').eq('id', id).maybeSingle();
        if (c == null) continue;
        var name = c['is_group'] == true ? '${c['title'] ?? 'Group'}' : 'GG User';
        final others = await sb.from('conversation_members').select('user_id').eq('conversation_id', id).neq('user_id', user.id).limit(1);
        if (others.isNotEmpty) {
          final p = await sb.from('profiles').select('display_name').eq('id', others.first['user_id']).maybeSingle();
          name = '${p?['display_name'] ?? name}';
        }
        final last = await sb.from('messages').select('body,created_at').eq('conversation_id', id).order('created_at', ascending: false).limit(1).maybeSingle();
        result.add(Conversation(id: '$id', name: name, message: '${last?['body'] ?? 'No messages yet'}', time: clock(last?['created_at'])));
      }
      await OfflineStore.saveHome(user.id, [for (final c in result) {'id': c.id, 'name': c.name, 'message': c.message, 'time': c.time}]);
      if (mounted) setState(() { chats = result; loading = false; });
    } catch (_) {
      final cached = await OfflineStore.loadHome(user.id);
      if (mounted) setState(() { chats = cached.map((x) => Conversation(id: '${x['id']}', name: '${x['name'] ?? 'GG User'}', message: '${x['message'] ?? ''}', time: '${x['time'] ?? ''}')).toList(); loading = false; });
    }
  }

  void _listenCalls() {
    final user = sb.auth.currentUser;
    if (user == null) return;
    incoming = CallsRepository(sb).subscribeToIncoming(user.id, (call) async {
      if (!mounted || call.status != 'ringing' || shown.contains(call.id)) return;
      shown.add(call.id);
      final video = call.type == 'video';
      final answer = await showDialog<bool>(context: context, barrierDismissible: false, builder: (c) => AlertDialog(
        title: Text(video ? 'Incoming video call' : 'Incoming voice call'),
        content: const Text('Someone is calling you.'),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Decline')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Answer'))],
      ));
      if (!mounted) return;
      if (answer == true) await Navigator.push(context, MaterialPageRoute(builder: (_) => CallPage(callId: call.id, video: video, caller: false)));
      else await CallsRepository(sb).setStatus(call.id, 'rejected');
    });
  }

  Future<String> _createDirect(String other) async {
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

  Future<void> _newChat() async {
    final controller = TextEditingController();
    await showDialog<void>(context: context, builder: (c) => AlertDialog(
      title: const Text('New conversation'),
      content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(prefixIcon: Icon(Icons.person_search_rounded), hintText: 'Name or username')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(onPressed: () async {
          final term = controller.text.trim(); if (term.isEmpty) return;
          try {
            final me = sb.auth.currentUser!.id;
            final users = await sb.from('profiles').select('id,display_name,username').neq('id', me).or('display_name.ilike.%$term%,username.ilike.%$term%').limit(20);
            if (!mounted) return; Navigator.pop(c);
            if (users.isEmpty) { _snack('No users found.'); return; }
            final selected = await showDialog<dynamic>(context: context, builder: (s) => SimpleDialog(title: const Text('Choose a person'), children: [for (final p in users) SimpleDialogOption(onPressed: () => Navigator.pop(s, p), child: Text('${p['display_name'] ?? 'GG User'}'))]));
            if (selected == null || !mounted) return;
            final id = await _createDirect('${selected['id']}');
            await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(conversation: Conversation(id: id, name: '${selected['display_name'] ?? 'GG User'}', message: '', time: ''), dark: dark)));
            _refresh();
          } catch (e) { _snack('$e'); }
        }, child: const Text('Search')),
      ],
    ));
    controller.dispose();
  }

  Future<void> _showProfile() async {
    final user = sb.auth.currentUser;
    var name = user?.userMetadata?['display_name']?.toString() ?? user?.email?.split('@').first ?? 'GG User';
    var username = user?.userMetadata?['username']?.toString() ?? '';
    try { if (user != null) { final p = await sb.from('profiles').select('display_name,username').eq('id', user.id).maybeSingle(); name = '${p?['display_name'] ?? name}'; username = '${p?['username'] ?? username}'; } } catch (_) {}
    if (!mounted) return;
    showDialog<void>(context: context, builder: (_) => AlertDialog(title: const Text('Profile'), content: Column(mainAxisSize: MainAxisSize.min, children: [CircleAvatar(radius: 34, child: Text(name.isEmpty ? 'G' : name[0].toUpperCase(), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold))), const SizedBox(height: 14), Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)), if (username.isNotEmpty) Text('@$username'), if (user?.email != null) Text(user!.email!, style: const TextStyle(fontSize: 12))]), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))]));
  }

  Future<void> _showSettings() async {
    await showDialog<void>(context: context, builder: (dc) => StatefulBuilder(builder: (_, setDialogState) => AlertDialog(title: const Text('Settings'), content: Column(mainAxisSize: MainAxisSize.min, children: [SwitchListTile(value: dark, onChanged: (v) { setState(() => dark = v); setDialogState(() {}); }, title: const Text('Dark mode'), secondary: const Icon(Icons.dark_mode_outlined)), const ListTile(leading: Icon(Icons.notifications_outlined), title: Text('Notifications')), const ListTile(leading: Icon(Icons.lock_outline), title: Text('Privacy'))]), actions: [TextButton(onPressed: () => Navigator.pop(dc), child: const Text('Done'))])));
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text('Log out?'), content: const Text('You can sign in again at any time.'), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Log out'))]));
    if (ok == true) { try { await sb.auth.signOut(); } catch (e) { if (mounted) _snack('$e'); } }
  }

  void _openMenu() => showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (c) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [ListTile(leading: const Icon(Icons.person), title: const Text('View profile'), onTap: () { Navigator.pop(c); _showProfile(); }), ListTile(leading: const Icon(Icons.settings), title: const Text('Settings'), onTap: () { Navigator.pop(c); _showSettings(); }), ListTile(leading: Icon(dark ? Icons.light_mode : Icons.dark_mode), title: Text(dark ? 'Light mode' : 'Dark mode'), onTap: () { setState(() => dark = !dark); Navigator.pop(c); }), const Divider(), ListTile(leading: const Icon(Icons.logout, color: Colors.redAccent), title: const Text('Logout', style: TextStyle(color: Colors.redAccent)), onTap: () { Navigator.pop(c); _logout(); })])));

  void _snack(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  @override
  void dispose() { search.dispose(); if (incoming != null) sb.removeChannel(incoming!); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final cs = dark ? const ColorScheme.dark(primary: Color(0xFFFFC83D), surface: Color(0xFF0B0C0F)) : ColorScheme.fromSeed(seedColor: const Color(0xFFFFB800));
    final filtered = chats.where((c) => c.name.toLowerCase().contains(search.text.toLowerCase()) || c.message.toLowerCase().contains(search.text.toLowerCase())).toList();
    return Theme(data: ThemeData(useMaterial3: true, colorScheme: cs, scaffoldBackgroundColor: cs.surface), child: Scaffold(
      appBar: AppBar(toolbarHeight: 82, titleSpacing: 20, title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('GG', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)), Text('${filtered.length} conversations', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))]), actions: [IconButton(tooltip: 'Profile', onPressed: _showProfile, icon: const Icon(Icons.person_outline_rounded)), IconButton(tooltip: 'Change theme', onPressed: () => setState(() => dark = !dark), icon: Icon(dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded)), IconButton(tooltip: 'More', onPressed: _openMenu, icon: const Icon(Icons.more_vert_rounded))]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 110), children: [TextField(controller: search, onChanged: (_) => setState(() {}), decoration: InputDecoration(hintText: 'Search chats', prefixIcon: const Icon(Icons.search_rounded), filled: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none))), const SizedBox(height: 22), Row(children: [const Text('Messages', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)), const Spacer(), Text('${filtered.length}', style: TextStyle(color: cs.primary))]), const SizedBox(height: 10), if (loading) ...List.generate(4, (_) => const ListTile(leading: CircleAvatar(), title: Text('Loading…'))) else if (filtered.isEmpty) const Padding(padding: EdgeInsets.only(top: 80), child: Center(child: Text('Your inbox is empty'))) else ...[for (final chat in filtered) ListTile(leading: CircleAvatar(child: Text(chat.name.isEmpty ? 'G' : chat.name[0].toUpperCase())), title: Text(chat.name, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text(chat.message, maxLines: 1, overflow: TextOverflow.ellipsis), trailing: Text(chat.time), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(conversation: chat, dark: dark))).then((_) => _refresh()))]],),
      floatingActionButton: FloatingActionButton.extended(onPressed: _newChat, icon: const Icon(Icons.edit_rounded), label: const Text('New chat')),
    ));
  }
}
