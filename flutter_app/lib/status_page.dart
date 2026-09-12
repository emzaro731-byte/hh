import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StatusPage extends StatefulWidget {
  const StatusPage({super.key});
  @override State<StatusPage> createState() => _StatusPageState();
}

class _StatusPageState extends State<StatusPage> {
  final sb = Supabase.instance.client;
  final picker = ImagePicker();
  bool loading = true, posting = false;
  List<Map<String, dynamic>> statuses = [];

  @override void initState() { super.initState(); load(); }

  Future<void> load() async {
    if (mounted) setState(() => loading = true);
    try {
      final rows = await sb.from('statuses').select('id,user_id,type,text,media_url,background,created_at,expires_at').gt('expires_at', DateTime.now().toUtc().toIso8601String()).order('created_at', ascending: false);
      if (mounted) setState(() => statuses = List<Map<String, dynamic>>.from(rows));
    } catch (e) { if (mounted) _snack('Could not load statuses: $e'); }
    if (mounted) setState(() => loading = false);
  }

  void _snack(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  Future<void> createText() async {
    final c = TextEditingController();
    final text = await showDialog<String>(context: context, builder: (_) => AlertDialog(
      title: const Text('New status'),
      content: TextField(controller: c, maxLines: 5, autofocus: true, decoration: const InputDecoration(hintText: 'What is happening?')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Post'))],
    ));
    c.dispose();
    if (text == null || text.isEmpty) return;
    await _insert(type: 'text', text: text);
  }

  Future<void> pickMedia({required bool video}) async {
    final file = video ? await picker.pickVideo(source: ImageSource.gallery) : await picker.pickImage(source: ImageSource.gallery, imageQuality: 88);
    if (file == null) return;
    if (mounted) setState(() => posting = true);
    try {
      final uid = sb.auth.currentUser!.id;
      final ext = file.path.split('.').last.toLowerCase();
      final path = '$uid/${DateTime.now().microsecondsSinceEpoch}.$ext';
      await sb.storage.from('status-media').upload(path, File(file.path), fileOptions: FileOptions(upsert: false, contentType: video ? 'video/$ext' : 'image/$ext'));
      final url = await sb.storage.from('status-media').createSignedUrl(path, 60 * 60 * 24);
      await _insert(type: video ? 'video' : 'image', mediaUrl: url);
    } catch (e) { if (mounted) _snack('Upload failed: $e'); }
    if (mounted) setState(() => posting = false);
  }

  Future<void> _insert({required String type, String? text, String? mediaUrl}) async {
    if (mounted) setState(() => posting = true);
    try {
      await sb.from('statuses').insert({'user_id': sb.auth.currentUser!.id, 'type': type, 'text': text, 'media_url': mediaUrl});
      await load();
    } catch (e) { if (mounted) _snack('Could not post status: $e'); }
    if (mounted) setState(() => posting = false);
  }

  Future<void> viewStatus(Map<String, dynamic> s) async {
    final me = sb.auth.currentUser?.id;
    if (me != null && me != s['user_id']) { try { await sb.from('status_views').upsert({'status_id': s['id'], 'viewer_id': me}); } catch (_) {} }
    if (!mounted) return;
    await showDialog(context: context, barrierColor: Colors.black87, builder: (_) => _StatusViewer(status: s));
  }

  Future<void> deleteStatus(Map<String, dynamic> s) async {
    try { await sb.from('statuses').delete().eq('id', s['id']); await load(); } catch (e) { _snack('Delete failed: $e'); }
  }

  @override Widget build(BuildContext context) {
    final me = sb.auth.currentUser?.id;
    final mine = statuses.where((s) => s['user_id'] == me).toList();
    final others = statuses.where((s) => s['user_id'] != me).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('GG Status'), actions: [IconButton(onPressed: load, icon: const Icon(Icons.refresh))]),
      body: RefreshIndicator(onRefresh: load, child: loading ? const Center(child: CircularProgressIndicator()) : ListView(padding: const EdgeInsets.all(12), children: [
        if (posting) const LinearProgressIndicator(),
        Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('My Status', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [FilledButton.icon(onPressed: posting ? null : createText, icon: const Icon(Icons.edit), label: const Text('Text')), OutlinedButton.icon(onPressed: posting ? null : () => pickMedia(video: false), icon: const Icon(Icons.photo), label: const Text('Photo')), OutlinedButton.icon(onPressed: posting ? null : () => pickMedia(video: true), icon: const Icon(Icons.videocam), label: const Text('Video'))]),
          if (mine.isNotEmpty) ...[const SizedBox(height: 12), SizedBox(height: 112, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: mine.length, separatorBuilder: (_, __) => const SizedBox(width: 10), itemBuilder: (_, i) => _StatusTile(status: mine[i], onTap: () => viewStatus(mine[i]), onDelete: () => deleteStatus(mine[i]))))]
        ]))),
        const Padding(padding: EdgeInsets.fromLTRB(4, 18, 4, 8), child: Text('Recent updates', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
        if (others.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('No recent status updates'))),
        for (final s in others) Card(child: ListTile(leading: _Avatar(status: s), title: const Text('GG User', style: TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(s['type'] == 'text' ? (s['text'] ?? '') : 'Tap to view ${s['type']} status', maxLines: 1, overflow: TextOverflow.ellipsis), onTap: () => viewStatus(s)))
      ])),
    );
  }
}

class _StatusTile extends StatelessWidget {
  final Map<String, dynamic> status; final VoidCallback onTap; final VoidCallback onDelete;
  const _StatusTile({required this.status, required this.onTap, required this.onDelete});
  @override Widget build(BuildContext context) => GestureDetector(onTap: onTap, onLongPress: onDelete, child: SizedBox(width: 92, child: Column(children: [Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(18), child: _Media(status: status))), const SizedBox(height: 5), Text(status['type'] == 'text' ? 'Text' : status['type'].toString().toUpperCase(), style: const TextStyle(fontSize: 12))])));
}

class _Avatar extends StatelessWidget { final Map<String,dynamic> status; const _Avatar({required this.status}); @override Widget build(BuildContext c) => CircleAvatar(radius: 26, child: status['type'] == 'image' ? ClipOval(child: Image.network(status['media_url'] ?? '', width: 52, height: 52, fit: BoxFit.cover, errorBuilder: (_,__,___) => const Icon(Icons.person))) : const Icon(Icons.person)); }
class _Media extends StatelessWidget { final Map<String,dynamic> status; const _Media({required this.status}); @override Widget build(BuildContext c) { final t=status['type']; if(t=='image') return Image.network(status['media_url']??'', fit:BoxFit.cover, width:double.infinity, errorBuilder:(_,__,___)=>const ColoredBox(color:Colors.black12,child:Icon(Icons.broken_image))); if(t=='video') return const ColoredBox(color:Colors.black87,child:Center(child:Icon(Icons.play_circle_fill,color:Colors.white,size:42))); return Container(color:const Color(0xff2563eb),padding:const EdgeInsets.all(8),alignment:Alignment.center,child:Text(status['text']??'',maxLines:3,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Colors.white,fontWeight:FontWeight.bold))); } }
class _StatusViewer extends StatelessWidget { final Map<String,dynamic> status; const _StatusViewer({required this.status}); @override Widget build(BuildContext c) => Dialog(backgroundColor:Colors.transparent, insetPadding:const EdgeInsets.all(18), child: Column(mainAxisSize:MainAxisSize.min, children:[Align(alignment:Alignment.centerRight,child:IconButton(color:Colors.white,onPressed:()=>Navigator.pop(c),icon:const Icon(Icons.close))), Container(constraints:const BoxConstraints(maxHeight:650), width:double.infinity, decoration:BoxDecoration(borderRadius:BorderRadius.circular(20)), clipBehavior:Clip.antiAlias, child:_Media(status:status)), if(status['type']=='text') Padding(padding:const EdgeInsets.all(14),child:Text(status['text']??'',style:const TextStyle(color:Colors.white,fontSize:20,fontWeight:FontWeight.w700))) ])); }
