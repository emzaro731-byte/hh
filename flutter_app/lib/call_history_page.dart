import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'call_page.dart';
import 'offline_store.dart';
import 'services/calls_repository.dart';

class CallHistoryPage extends StatefulWidget {
  const CallHistoryPage({super.key});
  @override State<CallHistoryPage> createState() => _CallHistoryPageState();
}

class _CallHistoryPageState extends State<CallHistoryPage> {
  final sb = Supabase.instance.client;
  bool loading = true;
  bool syncing = false;
  List<CallRecord> calls = [];
  Map<String, Map<String, dynamic>> profiles = {};

  @override void initState() { super.initState(); load(); }

  Future<void> load() async {
    final me = sb.auth.currentUser?.id;
    if (me == null) return;

    // Always paint the last known call history first. The UI stays usable with data off.
    final cachedCalls = await OfflineStore.loadCachedList(me, 'calls');
    final cachedProfiles = await OfflineStore.loadCachedList(me, 'call_profiles');
    if (cachedCalls.isNotEmpty || cachedProfiles.isNotEmpty) {
      profiles = {for (final p in cachedProfiles) '${p['id']}': p};
      calls = cachedCalls.map(CallRecord.fromMap).toList();
      if (mounted) setState(() { loading = false; syncing = true; });
    } else if (mounted) {
      setState(() { loading = true; syncing = true; });
    }

    try {
      final rows = await sb.from('calls').select().or('caller_id.eq.$me,callee_id.eq.$me').order('created_at', ascending: false).limit(100);
      final rawCalls = List<Map<String, dynamic>>.from(rows);
      final list = rawCalls.map(CallRecord.fromMap).toList();
      final ids = <String>{};
      for (final c in list) ids.add(c.callerId == me ? c.calleeId : c.callerId);

      Map<String, Map<String, dynamic>> nextProfiles = {};
      if (ids.isNotEmpty) {
        final ps = await sb.from('profiles').select('id,display_name,username,avatar_url').inFilter('id', ids.toList());
        nextProfiles = {for (final p in List<Map<String, dynamic>>.from(ps)) '${p['id']}': p};
      }

      await OfflineStore.saveCachedList(me, 'calls', rawCalls);
      await OfflineStore.saveCachedList(me, 'call_profiles', nextProfiles.values.toList());

      if (mounted) setState(() {
        calls = list;
        profiles = nextProfiles;
        loading = false;
        syncing = false;
      });
    } catch (_) {
      // Keep the cached screen exactly as it was. No destructive clearing on network loss.
      if (mounted) setState(() { loading = false; syncing = false; });
    }
  }

  String person(CallRecord c, String me) {
    final id = c.callerId == me ? c.calleeId : c.callerId;
    return '${profiles[id]?['display_name'] ?? profiles[id]?['username'] ?? 'GG User'}';
  }

  String time(String value) {
    final d = DateTime.tryParse(value)?.toLocal();
    if (d == null) return '';
    final now = DateTime.now();
    if (now.year == d.year && now.month == d.month && now.day == d.day) {
      return TimeOfDay.fromDateTime(d).format(context);
    }
    return '${d.day}/${d.month}/${d.year}';
  }

  bool outgoing(CallRecord c, String me) => c.callerId == me;

  String subtitle(CallRecord c, String me) {
    if (c.status == 'rejected') return outgoing(c, me) ? 'Cancelled' : 'Declined';
    if (c.status == 'ringing') return outgoing(c, me) ? 'No answer' : 'Missed call';
    if (c.status == 'active') return 'Call in progress';
    return outgoing(c, me) ? 'Outgoing call' : 'Incoming call';
  }

  Future<void> redial(CallRecord c, String me) async {
    final other = c.callerId == me ? c.calleeId : c.callerId;
    try {
      final type = c.type == 'video' ? 'video' : 'audio';
      final fresh = await CallsRepository(sb).createCall(other, type);
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => CallPage(callId: fresh.id, video: type == 'video', caller: true)));
      load();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You are offline. Call history is still available.')));
    }
  }

  @override Widget build(BuildContext context) {
    final me = sb.auth.currentUser?.id;
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [const Text('Calls', style: TextStyle(fontWeight: FontWeight.w800)), if (syncing) ...[const SizedBox(width: 8), const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))]]),
        actions: [IconButton(onPressed: load, tooltip: 'Sync', icon: const Icon(Icons.sync_rounded))],
      ),
      body: me == null
          ? const Center(child: Text('Sign in to view calls'))
          : loading
              ? const Center(child: CircularProgressIndicator())
              : calls.isEmpty
                  ? ListView(physics: const ClampingScrollPhysics(), children: const [SizedBox(height: 180), Icon(Icons.call_outlined, size: 64), SizedBox(height: 16), Center(child: Text('No call history yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)))])
                  : ListView.separated(
                      physics: const ClampingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 30),
                      itemCount: calls.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 4),
                      itemBuilder: (_, i) {
                        final c = calls[i]; final isOut = outgoing(c, me); final missed = c.status == 'ringing' && !isOut; final name = person(c, me);
                        return ListTile(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          tileColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .35),
                          leading: CircleAvatar(radius: 25, backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: .15), child: Text(name.isEmpty ? 'G' : name[0].toUpperCase(), style: TextStyle(fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary))),
                          title: Text(name, style: TextStyle(fontWeight: FontWeight.w800, color: missed ? Colors.redAccent : null)),
                          subtitle: Row(children: [Icon(isOut ? Icons.call_made_rounded : Icons.call_received_rounded, size: 16, color: missed ? Colors.redAccent : Colors.green), const SizedBox(width: 5), Text('${c.type == 'video' ? 'Video' : 'Voice'} · ${subtitle(c, me)}')]),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [Text(time(c.createdAt), style: Theme.of(context).textTheme.bodySmall), const SizedBox(width: 6), IconButton(onPressed: () => redial(c, me), icon: Icon(c.type == 'video' ? Icons.videocam_rounded : Icons.call_rounded))]),
                        );
                      },
                    ),
    );
  }
}
