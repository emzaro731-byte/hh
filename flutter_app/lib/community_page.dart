import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _green = Color(0xff00d084);
const _bg = Color(0xff090d11);

class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key});
  @override State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  final sb = Supabase.instance.client;
  List<Map<String, dynamic>> groups = [];
  bool loading = true;

  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    try {
      final u = sb.auth.currentUser;
      if (u == null) return;
      final ms = await sb.from('conversation_members').select('conversation_id').eq('user_id', u.id);
      final out = <Map<String, dynamic>>[];
      for (final m in ms) {
        final c = await sb.from('conversations').select('id,title,is_group').eq('id', m['conversation_id']).eq('is_group', true).maybeSingle();
        if (c != null) out.add(Map<String, dynamic>.from(c));
      }
      if (mounted) setState(() => groups = out);
    } catch (_) {}
    finally { if (mounted) setState(() => loading = false); }
  }

  Future<void> createGroup() async {
    final ctl = TextEditingController();
    await showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Create community'),
      content: TextField(controller: ctl, autofocus: true, decoration: const InputDecoration(labelText: 'Community name', hintText: 'e.g. GG Creators')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () async {
          final name = ctl.text.trim();
          if (name.isEmpty) return;
          try {
            final u = sb.auth.currentUser!;
            final c = await sb.from('conversations').insert({'title': name, 'is_group': true}).select('id').single();
            await sb.from('conversation_members').insert({'conversation_id': c['id'], 'user_id': u.id});
            if (context.mounted) Navigator.pop(context);
            load();
          } catch (e) {
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Create failed: $e')));
          }
        }, child: const Text('Create')),
      ],
    ));
    ctl.dispose();
  }

  Future<void> invite(String id, String name) async {
    try {
      final u = sb.auth.currentUser!;
      final token = '${u.id.substring(0, 8)}_${DateTime.now().millisecondsSinceEpoch}';
      await sb.from('conversation_invites').insert({'conversation_id': id, 'created_by': u.id, 'token': token});
      final link = 'gg://invite/$token';
      if (!mounted) return;
      showDialog(context: context, builder: (_) => AlertDialog(
        title: Text('Invite to $name'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [QrImageView(data: link, size: 190), const SizedBox(height: 12), SelectableText(link)]),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invite failed: $e'))); }
  }

  Future<void> join() async {
    final ctl = TextEditingController();
    await showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Join a community'),
      content: TextField(controller: ctl, decoration: const InputDecoration(hintText: 'Paste GG invite link or token')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () async {
          try {
            var token = ctl.text.trim();
            if (token.contains('/')) token = token.split('/').last;
            await sb.rpc('join_conversation_by_invite', params: {'invite_token': token});
            if (context.mounted) Navigator.pop(context);
            load();
          } catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Join failed: $e'))); }
        }, child: const Text('Join')),
      ],
    ));
    ctl.dispose();
  }

  Future<void> openGroup(Map<String, dynamic> group) async {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${group['title'] ?? 'Community'} opened')));
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark(useMaterial3: true).copyWith(scaffoldBackgroundColor: _bg, colorScheme: ColorScheme.fromSeed(seedColor: _green, brightness: Brightness.dark)),
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          title: const Text('Communities', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
          actions: [IconButton(onPressed: join, tooltip: 'Join with invite', icon: const Icon(Icons.link_rounded)), IconButton(onPressed: createGroup, tooltip: 'New community', icon: const Icon(Icons.add_rounded))],
        ),
        body: loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(
          onRefresh: load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
            children: [
              Row(children: [Container(width: 46, height: 46, decoration: BoxDecoration(color: _green.withOpacity(.16), shape: BoxShape.circle), child: const Icon(Icons.groups_rounded, color: _green, size: 27)), const SizedBox(width: 12), const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Bring people together', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)), SizedBox(height: 3), Text('Join communities that match your interests.', style: TextStyle(color: Colors.white60))]))]),
              const SizedBox(height: 18),
              SizedBox(height: 50, child: FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.black), onPressed: createGroup, icon: const Icon(Icons.add), label: const Text('New community', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)))),
              const SizedBox(height: 26),
              Row(children: [const Expanded(child: Text('Your communities', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))), TextButton(onPressed: join, child: const Text('Join'))]),
              if (groups.isEmpty)
                Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white12), color: const Color(0xff10161b)), child: Column(children: [const Icon(Icons.groups_outlined, size: 54, color: Colors.white38), const SizedBox(height: 10), const Text('No communities yet', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)), const SizedBox(height: 6), const Text('Create one or join with an invite link.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)), const SizedBox(height: 14), FilledButton(onPressed: createGroup, child: const Text('Create community'))]))
              else ...groups.map((g) => _CommunityCard(group: g, onTap: () => openGroup(g), onInvite: () => invite('${g['id']}', '${g['title'] ?? 'Community'}'))),
              const SizedBox(height: 22),
              const Text('Discover communities', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              const _DiscoverCard(icon: '🌍', title: 'GG Global', subtitle: 'Connect • Share • Grow together', members: '12.4K members'),
              const _DiscoverCard(icon: '🤖', title: 'Tech & AI', subtitle: 'AI • Tech • Innovation', members: '8.7K members'),
              const _DiscoverCard(icon: '🎵', title: 'Music & Creators', subtitle: 'Music • Art • Content creation', members: '15.2K members'),
              const _DiscoverCard(icon: '💼', title: 'Business & Hustle', subtitle: 'Business • Opportunities', members: '9.1K members'),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          backgroundColor: const Color(0xff090d11),
          selectedIndex: 2,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'Chats'),
            NavigationDestination(icon: Icon(Icons.circle_outlined), label: 'Updates'),
            NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups, color: _green), label: 'Communities'),
            NavigationDestination(icon: Icon(Icons.call_outlined), label: 'Calls'),
          ],
          onDestinationSelected: (index) { if (index != 2) Navigator.pop(context); },
        ),
      ),
    );
  }
}

class _CommunityCard extends StatelessWidget {
  final Map<String, dynamic> group; final VoidCallback onTap, onInvite;
  const _CommunityCard({required this.group, required this.onTap, required this.onInvite});
  @override Widget build(BuildContext context) => Card(color: const Color(0xff10161b), margin: const EdgeInsets.only(bottom: 9), child: ListTile(onTap: onTap, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5), leading: const CircleAvatar(backgroundColor: Color(0xff18352d), child: Icon(Icons.groups, color: _green)), title: Text('${group['title'] ?? 'Community'}', style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: const Text('Announcements • Groups', style: TextStyle(color: Colors.white60)), trailing: IconButton(onPressed: onInvite, icon: const Icon(Icons.qr_code_2))));
}

class _DiscoverCard extends StatelessWidget {
  final String icon, title, subtitle, members;
  const _DiscoverCard({required this.icon, required this.title, required this.subtitle, required this.members});
  @override Widget build(BuildContext context) => Card(color: const Color(0xff10161b), margin: const EdgeInsets.only(bottom: 9), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.white10)), child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4), leading: CircleAvatar(radius: 25, backgroundColor: const Color(0xff172329), child: Text(icon, style: const TextStyle(fontSize: 24))), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text('$subtitle\n$members', style: const TextStyle(color: Colors.white60, height: 1.3)), isThreeLine: true, trailing: FilledButton(onPressed: () {}, style: FilledButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.black), child: const Text('Join'))));
}
