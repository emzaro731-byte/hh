import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'offline_chat_page.dart';
import 'offline_store.dart';
import 'home_page.dart';
import 'call_page.dart';
import 'services/calls_repository.dart';

class PremiumHomePage extends StatefulWidget {
  const PremiumHomePage({super.key});
  @override
  State<PremiumHomePage> createState() => _PremiumHomePageState();
}

class _PremiumHomePageState extends State<PremiumHomePage> {
  final sb = Supabase.instance.client;
  final search = TextEditingController();
  List<Conversation> chats = [];
  bool loading = true;
  bool dark = true;
  RealtimeChannel? incoming;
  final Set<String> shown = {};

  @override
  void initState() {
    super.initState();
    _refresh();
    _listenCalls();
  }

  String clock(dynamic value) {
    if (value == null) return '';
    try { return TimeOfDay.fromDateTime(DateTime.parse(value.toString()).toLocal()).format(context); } catch (_) { return ''; }
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
        final conversation = await sb.from('conversations').select('id,title,is_group').eq('id', id).maybeSingle();
        if (conversation == null) continue;
        final others = await sb.from('conversation_members').select('user_id').eq('conversation_id', id).neq('user_id', user.id).limit(1);
        var name = conversation['is_group'] == true ? '${conversation['title'] ?? 'Group'}' : 'GG User';
        if (others.isNotEmpty) {
          final profile = await sb.from('profiles').select('display_name').eq('id', others.first['user_id']).maybeSingle();
          name = '${profile?['display_name'] ?? 'GG User'}';
        }
        final last = await sb.from('messages').select('body,created_at').eq('conversation_id', id).order('created_at', ascending: false).limit(1).maybeSingle();
        result.add(Conversation(id: '$id', name: name, message: '${last?['body'] ?? 'No messages yet'}', time: clock(last?['created_at'])));
      }
      await OfflineStore.saveHome(user.id, [for (final c in result) {'id': c.id, 'name': c.name, 'message': c.message, 'time': c.time}]);
      if (mounted) setState(() { chats = result; loading = false; });
    } catch (_) {
      final cached = await OfflineStore.loadHome(user.id);
      if (mounted) setState(() {
        chats = cached.map((x) => Conversation(id: '${x['id']}', name: '${x['name'] ?? 'GG User'}', message: '${x['message'] ?? ''}', time: '${x['time'] ?? ''}')).toList();
        loading = false;
      });
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
        builder: (c) => AlertDialog(
          title: Text(video ? 'Incoming video call' : 'Incoming voice call'),
          content: const Text('Someone is calling you.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Decline')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Answer')),
          ],
        ),
      );
      if (!mounted) return;
      if (answer == true) {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => CallPage(callId: call.id, video: video, caller: false)));
      } else {
        await CallsRepository(sb).setStatus(call.id, 'rejected');
      }
    });
  }

  Future<void> _newChat() async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('New conversation'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(prefixIcon: Icon(Icons.person_search_rounded), hintText: 'Name or username')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () async {
            final term = controller.text.trim();
            if (term.isEmpty) return;
            try {
              final me = sb.auth.currentUser!.id;
              final users = await sb.from('profiles').select('id,display_name,username').neq('id', me).or('display_name.ilike.%$term%,username.ilike.%$term%').limit(20);
              if (!mounted) return;
              Navigator.pop(c);
              if (users.isEmpty) { _snack('No users found.'); return; }
              final selected = await showDialog<dynamic>(context: context, builder: (s) => SimpleDialog(title: const Text('Choose a person'), children: [for (final p in users) SimpleDialogOption(onPressed: () => Navigator.pop(s, p), child: Text('${p['display_name'] ?? 'GG User'}'))]));
              if (selected == null || !mounted) return;
              final id = await _createDirect('${selected['id']}');
              await Navigator.push(context, MaterialPageRoute(builder: (_) => OfflineChatPage(conversation: Conversation(id: id, name: '${selected['display_name'] ?? 'GG User'}', message: '', time: ''), dark: dark)));
              _refresh();
            } catch (e) { _snack(e.toString()); }
          }, child: const Text('Search')),
        ],
      ),
    );
    controller.dispose();
  }

  Future<String> _createDirect(String other) async {
    final me = sb.auth.currentUser!.id;
    final mine = await sb.from('conversation_members').select('conversation_id').eq('user_id', me);
    for (final row in mine) {
      final member = await sb.from('conversation_members').select('user_id').eq('conversation_id', row['conversation_id']).eq('user_id', other).maybeSingle();
      if (member != null) {
        final conversation = await sb.from('conversations').select('id').eq('id', row['conversation_id']).eq('is_group', false).maybeSingle();
        if (conversation != null) return '${conversation['id']}';
      }
    }
    final conversation = await sb.from('conversations').insert({'is_group': false}).select('id').single();
    await sb.from('conversation_members').insert([{'conversation_id': conversation['id'], 'user_id': me}, {'conversation_id': conversation['id'], 'user_id': other}]);
    return '${conversation['id']}';
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  void dispose() {
    search.dispose();
    if (incoming != null) sb.removeChannel(incoming!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = dark ? const ColorScheme.dark(primary: Color(0xFFFFC83D), surface: Color(0xFF0B0C0F)) : ColorScheme.fromSeed(seedColor: const Color(0xFFFFB800));
    final filtered = chats.where((c) => c.name.toLowerCase().contains(search.text.toLowerCase()) || c.message.toLowerCase().contains(search.text.toLowerCase())).toList();
    return Theme(
      data: ThemeData(useMaterial3: true, colorScheme: cs, scaffoldBackgroundColor: cs.surface),
      child: Scaffold(
        appBar: AppBar(
          elevation: 0,
          toolbarHeight: 82,
          titleSpacing: 20,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('GG', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -1.2)),
            Text('${filtered.length} conversations', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w500)),
          ]),
          actions: [
            IconButton(tooltip: 'Change theme', onPressed: () => setState(() => dark = !dark), icon: Icon(dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded)),
            const SizedBox(width: 10),
          ],
        ),
        body: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 110),
          children: [
            TextField(
              controller: search,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search chats',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: search.text.isNotEmpty ? IconButton(onPressed: () { search.clear(); setState(() {}); }, icon: const Icon(Icons.close_rounded)) : null,
                filled: true,
                fillColor: cs.surfaceContainerHighest.withValues(alpha: .62),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 15),
              ),
            ),
            const SizedBox(height: 22),
            Row(children: [const Text('Messages', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)), const Spacer(), Text('${filtered.length}', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w800))]),
            const SizedBox(height: 10),
            if (loading)
              ...List.generate(5, (_) => _skeleton(cs))
            else if (filtered.isEmpty)
              Padding(padding: const EdgeInsets.only(top: 80), child: Column(children: [Container(width: 82, height: 82, decoration: BoxDecoration(shape: BoxShape.circle, color: cs.primary.withValues(alpha: .12)), child: Icon(Icons.chat_bubble_outline_rounded, size: 38, color: cs.primary)), const SizedBox(height: 18), const Text('Your inbox is empty', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)), const SizedBox(height: 7), Text('Start a private conversation with someone.', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)), const SizedBox(height: 22), FilledButton.icon(onPressed: _newChat, icon: const Icon(Icons.add_rounded), label: const Text('Start a chat'))]))
            else
              ...[for (final chat in filtered) _chatTile(chat, cs)],
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(onPressed: _newChat, elevation: 5, icon: const Icon(Icons.edit_rounded), label: const Text('New chat', style: TextStyle(fontWeight: FontWeight.w800))),
      ),
    );
  }

  Widget _skeleton(ColorScheme cs) => Container(
    height: 76,
    margin: const EdgeInsets.symmetric(vertical: 5),
    decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .35), borderRadius: BorderRadius.circular(20)),
    child: Row(children: [const SizedBox(width: 14), Container(width: 52, height: 52, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white10)), const SizedBox(width: 14), Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Container(height: 12, width: 130, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8))), const SizedBox(height: 9), Container(height: 10, width: 190, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)))]))]),
  );

  Widget _chatTile(Conversation chat, ColorScheme cs) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Material(
      color: cs.surfaceContainerHighest.withValues(alpha: .42),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OfflineChatPage(conversation: chat, dark: dark))).then((_) => _refresh()),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11), child: Row(children: [
          Stack(children: [CircleAvatar(radius: 27, backgroundColor: cs.primary.withValues(alpha: .16), child: Text(chat.name.isEmpty ? 'G' : chat.name[0].toUpperCase(), style: TextStyle(color: cs.primary, fontSize: 18, fontWeight: FontWeight.w900))), Positioned(right: 1, bottom: 1, child: Container(width: 12, height: 12, decoration: BoxDecoration(color: const Color(0xFF32D583), shape: BoxShape.circle, border: Border.all(color: cs.surface, width: 2))))]),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(chat.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)), const SizedBox(height: 5), Text(chat.message.isEmpty ? 'Start a conversation' : chat.message, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant))])),
          const SizedBox(width: 8),
          Text(chat.time, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
        ])),
      ),
    ),
  );
}
