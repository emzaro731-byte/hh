import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class AIPage extends StatefulWidget {
  const AIPage({super.key});
  @override
  State<AIPage> createState() => _AIPageState();
}

class _Model { final String id, name, tag; const _Model(this.id, this.name, this.tag); }

class _AIPageState extends State<AIPage> {
  final sb = Supabase.instance.client;
  final prompt = TextEditingController();
  String mode = 'chat';
  String model = 'openai/gpt-oss-120b';
  String status = '';
  bool loading = false, downloading = false;
  Map<String, dynamic>? result;
  List<dynamic> history = [];

  static const chatModels = [
    _Model('openai/gpt-oss-120b', 'GPT OSS 120B', 'Expert'),
    _Model('openai/gpt-oss-20b', 'GPT OSS 20B', 'Fast'),
    _Model('llama-3.3-70b-versatile', 'Llama 3.3 70B', 'Expert'),
    _Model('llama-3.1-8b-instant', 'Llama 3.1 8B', 'Fast'),
    _Model('qwen/qwen3-32b', 'Qwen 3 32B', 'Balanced'),
  ];
  static const imageModels = [
    _Model('seedream/5.0-lite', 'Seedream 5 Lite', 'Fast'),
    _Model('seedream/5.0-pro', 'Seedream 5 Pro', 'Expert'),
    _Model('google/imagen4-fast', 'Imagen 4 Fast', 'Fast'),
    _Model('google/imagen4', 'Imagen 4', 'Expert'),
    _Model('google/nano-banana-2', 'Nano Banana 2', 'Fast'),
    _Model('google/nano-banana-pro', 'Nano Banana Pro', 'Expert'),
    _Model('flux-2/flex-text-to-image', 'Flux 2 Flex', 'Balanced'),
    _Model('flux-2/pro-text-to-image', 'Flux 2 Pro', 'Expert'),
    _Model('grok-imagine/text-to-image', 'Grok Imagine', 'Premium'),
    _Model('gpt-image-2', 'GPT Image 2', 'Premium'),
  ];
  static const videoModels = [
    _Model('kling-3.0', 'Kling 3.0', 'Expert'),
    _Model('kling/v3-turbo-text-to-video', 'Kling V3 Turbo', 'Fast'),
    _Model('kling-2.6/text-to-video', 'Kling 2.6', 'Balanced'),
    _Model('veo3/veo-3.1-fast', 'Veo 3.1 Fast', 'Fast'),
    _Model('veo3/veo-3.1-quality', 'Veo 3.1 Quality', 'Expert'),
    _Model('pixverse/v6-text-to-video', 'PixVerse V6', 'Fast'),
    _Model('wan/2.7-text-to-video', 'Wan 2.7', 'Balanced'),
    _Model('runway', 'Runway', 'Premium'),
    _Model('grok-imagine/text-to-video', 'Grok Imagine', 'Premium'),
    _Model('seedance/2.0', 'Seedance 2.0', 'Expert'),
  ];
  static const musicModels = [
    _Model('V6', 'Suno V6', 'Newest'), _Model('V6_MINI', 'Suno V6 Mini', 'Fast'),
    _Model('V6_WILD', 'Suno V6 Wild', 'Creative'), _Model('V5_5', 'Suno V5.5', 'Expert'),
    _Model('V5', 'Suno V5', 'Balanced'), _Model('V4_5ALL', 'Suno V4.5 All', 'Creative'),
    _Model('V4_5PLUS', 'Suno V4.5 Plus', 'Premium'), _Model('V4_5', 'Suno V4.5', 'Balanced'),
    _Model('V4', 'Suno V4', 'Classic'),
  ];

  List<_Model> get models => mode == 'chat' ? chatModels : mode == 'image' ? imageModels : mode == 'video' ? videoModels : musicModels;
  _Model get selected => models.firstWhere((m) => m.id == model, orElse: () => models.first);

  @override void initState() { super.initState(); loadHistory(); }
  @override void dispose() { prompt.dispose(); super.dispose(); }

  Future<void> loadHistory() async {
    try {
      final d = await sb.from('ai_generations').select('id,type,prompt,model,result_urls,result_text,created_at').order('created_at', ascending: false).limit(30);
      if (mounted) setState(() => history = d);
    } catch (_) {}
  }

  void chooseMode(String value) {
    setState(() {
      mode = value; result = null; status = '';
      model = (value == 'chat' ? chatModels : value == 'image' ? imageModels : value == 'video' ? videoModels : musicModels).first.id;
    });
  }

  Future<void> chooseModel() async {
    final picked = await showModalBottomSheet<String>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (_) => _ModelSheet(mode: mode, models: models, selected: model),
    );
    if (picked != null && mounted) setState(() => model = picked);
  }

  void setPreset(String preset) {
    final list = models;
    _Model pick = list.first;
    if (preset == 'fast') pick = list.firstWhere((m) => m.tag == 'Fast', orElse: () => list.first);
    if (preset == 'expert') pick = list.firstWhere((m) => m.tag == 'Expert' || m.tag == 'Premium', orElse: () => list.first);
    setState(() => model = pick.id);
  }

  Future<void> run() async {
    final text = prompt.text.trim();
    if (text.isEmpty || loading) return;
    setState(() { loading = true; status = 'Starting $model…'; result = null; });
    try {
      var done = Map<String, dynamic>.from((await sb.functions.invoke('ai-generate', body: {
        'type': mode, 'prompt': text, 'options': {'model': model, 'aspectRatio': mode == 'video' ? '9:16' : '1:1', 'duration': 5, 'quality': '720p'},
      })).data ?? {});
      if (mode != 'chat') {
        final task = done['taskId'];
        if (task == null) throw Exception('No generation task was returned');
        final started = DateTime.now();
        while (DateTime.now().difference(started) < const Duration(minutes: 15)) {
          await Future.delayed(const Duration(seconds: 2));
          final s = await sb.functions.invoke('ai-generate', body: {'action': 'status', 'type': mode, 'taskId': task});
          done = Map<String, dynamic>.from(s.data ?? {});
          if (mounted) setState(() => status = done['status']?.toString() ?? 'Generating…');
          final state = (done['status'] ?? '').toString().toLowerCase();
          if (done['url'] != null || (done['urls'] is List && (done['urls'] as List).isNotEmpty) || ['success','succeeded','complete','completed'].contains(state)) break;
        }
      }
      await sb.functions.invoke('ai-save', body: {'type': mode, 'prompt': text, 'model': model, 'taskId': done['taskId'], 'urls': done['urls'] ?? (done['url'] != null ? [done['url']] : []), 'resultText': done['message']});
      if (mounted) setState(() { result = done; status = 'Complete'; });
      await loadHistory();
    } catch (e) {
      if (mounted) setState(() { result = {'message': e.toString()}; status = 'Failed'; });
    } finally { if (mounted) setState(() => loading = false); }
  }

  IconData icon(String value) => value == 'image' ? Icons.image_outlined : value == 'video' ? Icons.movie_creation_outlined : value == 'music' ? Icons.music_note_rounded : Icons.auto_awesome;
  String title(String value) => value.isEmpty ? 'AI' : value[0].toUpperCase() + value.substring(1);
  List<String> urlsFrom(dynamic value) => value is List ? value.where((x) => x != null && x.toString().isNotEmpty).map((x) => x.toString()).toList() : value is String && value.isNotEmpty ? [value] : [];
  List<String> urls(Map<String, dynamic>? value) { if (value == null) return []; final a = urlsFrom(value['urls']); if (a.isNotEmpty) return a; final b = urlsFrom(value['result_urls']); return b.isNotEmpty ? b : urlsFrom(value['url']); }

  Future<void> open(String url) async => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  String extFor(String type, String url) { final c = url.split('?').first.toLowerCase(); final d = c.lastIndexOf('.'); if (d > 0 && d < c.length - 1 && c.length - d <= 6) return c.substring(d + 1); return type == 'image' ? 'jpg' : type == 'video' ? 'mp4' : 'mp3'; }

  Future<void> download(String url, String type) async {
    if (downloading) return; setState(() => downloading = true);
    try {
      final client = HttpClient(); final req = await client.getUrl(Uri.parse(url)); final res = await req.close();
      if (res.statusCode < 200 || res.statusCode >= 300) throw Exception('Server returned ${res.statusCode}');
      final b = BytesBuilder(); await for (final chunk in res) { b.add(chunk); }
      final ext = extFor(type, url); final name = 'gg_${type}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final saved = await FilePicker.platform.saveFile(dialogTitle: 'Save ${title(type)}', fileName: name, bytes: Uint8List.fromList(b.takeBytes()));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(saved == null ? 'Download cancelled' : '${title(type)} saved successfully')));
      client.close(force: true);
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $e'))); }
    finally { if (mounted) setState(() => downloading = false); }
  }

  Widget mediaActions(List<String> media) => Wrap(spacing: 8, runSpacing: 8, children: [
    for (final u in media) FilledButton.tonalIcon(onPressed: () => open(u), icon: Icon(mode == 'video' ? Icons.play_circle : mode == 'music' ? Icons.headphones : Icons.open_in_new), label: Text(mode == 'video' ? 'Watch' : mode == 'music' ? 'Listen' : 'Open')),
    for (final u in media) FilledButton.icon(onPressed: downloading ? null : () => download(u, mode), icon: Icon(downloading ? Icons.hourglass_top : Icons.download_rounded), label: Text(downloading ? 'Saving…' : 'Download')),
  ]);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme; final media = urls(result);
    const modes = ['chat','image','video','music'];
    return Scaffold(
      appBar: AppBar(title: const Text('GG AI Studio', style: TextStyle(fontWeight: FontWeight.w900)), actions: [IconButton(onPressed: loading ? null : loadHistory, icon: const Icon(Icons.history))]),
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(16,14,16,8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Expanded(child: Text('Create with AI', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),), Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(20)), child: const Text('PREMIUM', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)))]),
          const SizedBox(height: 5), Text('One studio. Multiple models. Switch anytime.', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 16),
          SizedBox(height: 72, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: modes.length, separatorBuilder: (_,__) => const SizedBox(width: 8), itemBuilder: (_,i) { final v=modes[i]; final sel=mode==v; return GestureDetector(onTap: loading?null:()=>chooseMode(v), child: AnimatedContainer(duration: const Duration(milliseconds:180), width: 92, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: sel?cs.primaryContainer:cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(18), border: Border.all(color: sel?cs.primary:cs.outlineVariant)), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon(v), size: 20, color: sel?cs.primary:null), const SizedBox(height:4), Text(title(v), style: const TextStyle(fontWeight: FontWeight.w800))]))); })),
          const SizedBox(height: 12),
          Card(elevation: 0, child: InkWell(borderRadius: BorderRadius.circular(16), onTap: loading?null:chooseModel, child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [CircleAvatar(child: Icon(icon(mode))), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('AI model', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)), Text(selected.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)), Text('${selected.tag} • ${selected.id}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant))]), const Icon(Icons.keyboard_arrow_down_rounded)]))),
          const SizedBox(height: 10),
          Row(children: [for (final p in ['auto','fast','expert']) Expanded(child: Padding(padding: const EdgeInsets.only(right: 7), child: OutlinedButton(onPressed: loading?null:()=>p=='auto'?setState((){}):setPreset(p), child: Text(p[0].toUpperCase()+p.substring(1)))))]),
          const SizedBox(height: 10),
          Card(elevation: 0, child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(mode=='chat'?'Ask GG AI anything':'Describe your ${title(mode)}', style: const TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height:10), TextField(controller: prompt, minLines:4, maxLines:8, enabled: !loading, decoration: InputDecoration(hintText: mode=='chat'?'Write your question…':'Describe exactly what you want…', filled:true, border:OutlineInputBorder(borderRadius:BorderRadius.circular(18)))), const SizedBox(height:12), SizedBox(width:double.infinity,height:52,child:FilledButton.icon(onPressed:loading?null:run, icon:Icon(loading?Icons.hourglass_top:Icons.auto_awesome), label:Text(loading?'Creating…':mode=='chat'?'Ask GG AI':'Generate ${title(mode)}')))]))),
        ]))),
        if (loading) const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(22), child: Center(child: CircularProgressIndicator()))),
        if (status.isNotEmpty && !loading) SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(16,8,16,4), child: Text(status, style: const TextStyle(fontWeight: FontWeight.w800)))),
        if (result != null) SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(16), child: Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children:[Icon(icon(mode)),const SizedBox(width:8),Text('${title(mode)} result',style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900))]), const SizedBox(height:12), if(result!['message']!=null) Text(result!['message'].toString(),style:const TextStyle(fontSize:15,height:1.45)), if(media.isNotEmpty&&mode=='image') ClipRRect(borderRadius:BorderRadius.circular(16),child:Image.network(media.first,width:double.infinity,height:280,fit:BoxFit.cover,errorBuilder:(_,__,___)=>const SizedBox(height:120,child:Center(child:Text('Image preview unavailable'))))), if(media.isNotEmpty) Padding(padding:const EdgeInsets.only(top:12),child:mediaActions(media))]))))),
        if (history.isNotEmpty) SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(16,12,16,30), child: Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('Recent creations',style:TextStyle(fontSize:20,fontWeight:FontWeight.w900)),const SizedBox(height:8),for(final h in history) Card(margin:const EdgeInsets.only(bottom:8),child:ExpansionTile(leading:CircleAvatar(child:Icon(icon('${h['type']??'chat'}'),size:20)),title:Text('${h['prompt']??''}',maxLines:2,overflow:TextOverflow.ellipsis),subtitle:Text('${title('${h['type']??'chat'}')} • ${h['model']??'GG AI'}'),children:[if(urlsFrom(h['result_urls']).isNotEmpty) Padding(padding:const EdgeInsets.fromLTRB(16,0,16,14),child:mediaActions(urlsFrom(h['result_urls']))),if((h['result_text']??'').toString().isNotEmpty) Padding(padding:const EdgeInsets.fromLTRB(16,0,16,14),child:Align(alignment:Alignment.centerLeft,child:Text(h['result_text'].toString()))) ]))]))),
      ]),
    );
  }
}

class _ModelSheet extends StatefulWidget {
  final String mode, selected; final List<_Model> models;
  const _ModelSheet({required this.mode, required this.models, required this.selected});
  @override State<_ModelSheet> createState() => _ModelSheetState();
}
class _ModelSheetState extends State<_ModelSheet> {
  String query='';
  @override Widget build(BuildContext context) {
    final list=widget.models.where((m)=>'${m.name} ${m.id} ${m.tag}'.toLowerCase().contains(query.toLowerCase())).toList();
    return SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(16,4,16,16),child: Column(mainAxisSize:MainAxisSize.min,children:[Row(children:[const Expanded(child:Text('Choose model',style:TextStyle(fontSize:22,fontWeight:FontWeight.w900))),Text('${widget.models.length} models')]),const SizedBox(height:10),TextField(onChanged:(v)=>setState(()=>query=v),decoration:InputDecoration(prefixIcon:const Icon(Icons.search),hintText:'Search models…',filled:true,border:OutlineInputBorder(borderRadius:BorderRadius.circular(16)))),const SizedBox(height:8),Flexible(child:ListView.builder(shrinkWrap:true,itemCount:list.length,itemBuilder:(_,i){final m=list[i];final sel=m.id==widget.selected;return ListTile(leading:CircleAvatar(child:Icon(widget.mode=='image'?Icons.image:widget.mode=='video'?Icons.movie:widget.mode=='music'?Icons.music_note:Icons.auto_awesome)),title:Text(m.name,style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('${m.tag} • ${m.id}',maxLines:1,overflow:TextOverflow.ellipsis),trailing:sel?const Icon(Icons.check_circle):null,onTap:()=>Navigator.pop(context,m.id));}))])));
  }
}
