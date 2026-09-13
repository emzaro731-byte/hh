import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class AIStudioPage extends StatefulWidget {
  const AIStudioPage({super.key});
  @override
  State<AIStudioPage> createState() => _AIStudioPageState();
}

class _Model {
  final String id, name, tag;
  const _Model(this.id, this.name, this.tag);
}

class _AIStudioPageState extends State<AIStudioPage> {
  final sb = Supabase.instance.client;
  final prompt = TextEditingController();
  final scroll = ScrollController();

  static const chatModels = <_Model>[
    _Model('openai/gpt-oss-120b', 'GPT OSS 120B', 'Powerful'),
    _Model('openai/gpt-oss-20b', 'GPT OSS 20B', 'Fast'),
    _Model('qwen/qwen3-32b', 'Qwen 3 32B', 'Balanced'),
  ];
  static const imageModels = <_Model>[
    _Model('seedream/5.0-lite', 'Seedream 5 Lite', 'Fast'),
    _Model('seedream/5.0-pro', 'Seedream 5 Pro', 'Pro'),
    _Model('google/imagen4-fast', 'Imagen 4 Fast', 'Fast'),
    _Model('google/imagen4', 'Imagen 4', 'Pro'),
    _Model('google/nano-banana-2', 'Nano Banana 2', 'Fast'),
    _Model('google/nano-banana-pro', 'Nano Banana Pro', 'Pro'),
    _Model('flux-2/flex-text-to-image', 'Flux 2 Flex', 'Balanced'),
    _Model('flux-2/pro-text-to-image', 'Flux 2 Pro', 'Pro'),
    _Model('grok-imagine/text-to-image', 'Grok Imagine', 'Premium'),
    _Model('gpt-image-2', 'GPT Image 2', 'Premium'),
  ];
  static const videoModels = <_Model>[
    _Model('kling-3.0', 'Kling 3.0', 'Pro'),
    _Model('kling/v3-turbo-text-to-video', 'Kling V3 Turbo', 'Fast'),
    _Model('kling-2.6/text-to-video', 'Kling 2.6', 'Balanced'),
    _Model('veo3/veo-3.1-fast', 'Veo 3.1 Fast', 'Fast'),
    _Model('veo3/veo-3.1-quality', 'Veo 3.1 Quality', 'Pro'),
    _Model('pixverse/v6-text-to-video', 'PixVerse V6', 'Fast'),
    _Model('wan/2.7-text-to-video', 'Wan 2.7', 'Balanced'),
    _Model('runway', 'Runway', 'Premium'),
    _Model('grok-imagine/text-to-video', 'Grok Imagine', 'Premium'),
    _Model('seedance/2.0', 'Seedance 2.0', 'Pro'),
  ];
  static const musicModels = <_Model>[
    _Model('V6', 'Suno V6', 'Newest'),
    _Model('V6_MINI', 'Suno V6 Mini', 'Fast'),
    _Model('V6_WILD', 'Suno V6 Wild', 'Creative'),
    _Model('V5_5', 'Suno V5.5', 'Pro'),
    _Model('V5', 'Suno V5', 'Balanced'),
    _Model('V4_5ALL', 'Suno V4.5 All', 'Creative'),
    _Model('V4_5PLUS', 'Suno V4.5 Plus', 'Premium'),
    _Model('V4_5', 'Suno V4.5', 'Balanced'),
    _Model('V4', 'Suno V4', 'Classic'),
  ];

  String mode = 'chat';
  String model = 'openai/gpt-oss-120b';
  bool loading = false;
  bool menuOpen = false;
  bool showHistory = false;
  String status = '';
  Map<String, dynamic>? result;
  List<Map<String, dynamic>> turns = [];
  List<dynamic> history = [];
  List<PlatformFile> attachments = [];

  List<_Model> get models => mode == 'chat' ? chatModels : mode == 'image' ? imageModels : mode == 'video' ? videoModels : musicModels;
  _Model get selected => models.firstWhere((m) => m.id == model, orElse: () => models.first);

  @override
  void initState() { super.initState(); loadHistory(); }
  @override
  void dispose() { prompt.dispose(); scroll.dispose(); super.dispose(); }

  Future<void> loadHistory() async {
    try {
      final d = await sb.from('ai_generations').select('id,type,prompt,model,result_urls,result_text,created_at').order('created_at', ascending: false).limit(40);
      if (mounted) setState(() => history = List<dynamic>.from(d));
    } catch (_) {}
  }

  void newChat() {
    setState(() { turns.clear(); result = null; status = ''; prompt.clear(); attachments.clear(); showHistory = false; menuOpen = false; });
  }

  List<_Model> modelsFor(String v) => v == 'chat' ? chatModels : v == 'image' ? imageModels : v == 'video' ? videoModels : musicModels;
  void selectMode(String v) => setState(() { mode = v; model = modelsFor(v).first.id; result = null; status = ''; });

  Future<void> chooseModel() async {
    final picked = await showModalBottomSheet<String>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => _ModelPicker(models: models, selected: model, mode: mode));
    if (picked != null && mounted) setState(() => model = picked);
  }

  Future<void> pickFiles() async {
    final p = await FilePicker.platform.pickFiles(allowMultiple: true, withData: false);
    if (p != null && mounted) setState(() => attachments = p.files);
  }

  Future<void> run() async {
    final text = prompt.text.trim();
    if (text.isEmpty || loading) return;
    setState(() { loading = true; status = mode == 'chat' ? 'Thinking…' : 'Creating…'; result = null; turns.add({'role': 'user', 'text': text}); });
    prompt.clear();
    _scrollBottom();
    try {
      var done = Map<String, dynamic>.from((await sb.functions.invoke('ai-generate', body: {'type': mode, 'prompt': text, 'options': {'model': model, 'aspectRatio': mode == 'video' ? '9:16' : '1:1', 'duration': 5, 'quality': '720p'}})).data ?? {});
      if (mode != 'chat') {
        final task = done['taskId'];
        if (task == null) throw Exception('No generation task was returned');
        final started = DateTime.now();
        while (DateTime.now().difference(started) < const Duration(minutes: 15)) {
          await Future.delayed(const Duration(seconds: 2));
          final s = await sb.functions.invoke('ai-generate', body: {'action': 'status', 'type': mode, 'taskId': task, 'options': {'model': model}});
          done = Map<String, dynamic>.from(s.data ?? {});
          if (mounted) setState(() => status = '${done['status'] ?? 'Generating…'}');
          final state = '${done['status'] ?? ''}'.toLowerCase();
          if (done['url'] != null || (done['urls'] is List && (done['urls'] as List).isNotEmpty) || ['success','succeeded','complete','completed'].contains(state)) break;
        }
      }
      await sb.functions.invoke('ai-save', body: {'type': mode, 'prompt': text, 'model': model, 'taskId': done['taskId'], 'urls': done['urls'] ?? (done['url'] != null ? [done['url']] : []), 'resultText': done['message']});
      if (mounted) setState(() { result = done; status = 'Complete'; if (mode == 'chat' && done['message'] != null) turns.add({'role': 'assistant', 'text': done['message'].toString()}); });
      await loadHistory();
      _scrollBottom();
    } catch (e) {
      if (mounted) setState(() { status = 'Failed'; result = {'message': e.toString()}; turns.add({'role': 'assistant', 'text': 'Sorry, something went wrong. $e'}); });
    } finally { if (mounted) setState(() => loading = false); }
  }

  void _scrollBottom() => WidgetsBinding.instance.addPostFrameCallback((_) { if (scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut); });
  IconData icon(String v) => v == 'image' ? Icons.image_outlined : v == 'video' ? Icons.movie_creation_outlined : v == 'music' ? Icons.music_note_rounded : Icons.auto_awesome;
  String label(String v) => v.isEmpty ? 'AI' : '${v[0].toUpperCase()}${v.substring(1)}';
  List<String> urls(dynamic v) { if (v is List) return v.where((x) => x != null && '$x'.isNotEmpty).map((x) => '$x').toList(); if (v is String && v.isNotEmpty) return [v]; return []; }
  List<String> resultUrls() { if (result == null) return []; final a = urls(result!['urls']); if (a.isNotEmpty) return a; final b = urls(result!['result_urls']); if (b.isNotEmpty) return b; return urls(result!['url']); }

  Future<void> openUrl(String u) async => launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
  String ext(String type, String u) { final p = u.split('?').first; final i = p.lastIndexOf('.'); if (i > 0 && p.length - i <= 6) return p.substring(i + 1); return type == 'video' ? 'mp4' : type == 'music' ? 'mp3' : 'jpg'; }
  Future<void> saveUrl(String u) async { try { final c = HttpClient(); final r = await (await c.getUrl(Uri.parse(u))).close(); final b = BytesBuilder(); await for (final x in r) b.add(x); final s = await FilePicker.platform.saveFile(fileName: 'gg_ai_${DateTime.now().millisecondsSinceEpoch}.${ext(mode,u)}', bytes: Uint8List.fromList(b.takeBytes())); c.close(force: true); if (mounted && s != null) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved successfully'))); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e'))); } }

  Widget header() {
    return SafeArea(child: Container(height: 64, padding: const EdgeInsets.symmetric(horizontal: 10), decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor))), child: Row(children: [IconButton(onPressed: () => setState(() => menuOpen = true), icon: const Icon(Icons.menu_rounded)), Expanded(child: InkWell(onTap: chooseModel, child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('GG AI', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)), Row(children: [Flexible(child: Text(selected.name, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant))), const Icon(Icons.keyboard_arrow_down_rounded, size: 17)])]))), IconButton(onPressed: loadHistory, icon: const Icon(Icons.history_rounded)), IconButton(onPressed: newChat, tooltip: 'New chat', icon: const Icon(Icons.edit_square_rounded))]));
  }

  Widget sidePanel() {
    return Stack(children: [if (menuOpen) Positioned.fill(child: GestureDetector(onTap: () => setState(() => menuOpen = false), child: Container(color: Colors.black54))), AnimatedPositioned(duration: const Duration(milliseconds: 220), left: menuOpen ? 0 : -315, top: 0, bottom: 0, child: Material(elevation: 24, child: SafeArea(child: SizedBox(width: 305, child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [Row(children: [const Expanded(child: Text('GG AI Studio', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900))), IconButton(onPressed: () => setState(() => menuOpen = false), icon: const Icon(Icons.close))]), FilledButton.icon(onPressed: newChat, style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 50)), icon: const Icon(Icons.add), label: const Text('New chat')), const SizedBox(height: 14), const Align(alignment: Alignment.centerLeft, child: Text('Create', style: TextStyle(fontWeight: FontWeight.w800))), for (final v in ['chat','image','video','music']) ListTile(leading: Icon(icon(v)), title: Text(label(v)), selected: mode == v, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), onTap: () { selectMode(v); setState(() => menuOpen = false); }), const Divider(), const Align(alignment: Alignment.centerLeft, child: Text('Recent', style: TextStyle(fontWeight: FontWeight.w800))), Expanded(child: ListView.builder(itemCount: history.length, itemBuilder: (_,i) { final h=history[i]; return ListTile(dense:true, leading: Icon(icon('${h['type'] ?? 'chat'}'), size:18), title: Text('${h['prompt'] ?? ''}', maxLines:2, overflow:TextOverflow.ellipsis), onTap: () => setState(() => menuOpen=false)); }))]))))));]);
  }

  Widget welcome() {
    final cs = Theme.of(context).colorScheme;
    final suggestions = mode == 'chat' ? ['Explain something simply', 'Write a professional message', 'Help me plan a project', 'Analyze an idea'] : mode == 'image' ? ['Cinematic portrait', 'Product advertisement', 'Anime artwork', 'Photorealistic scene'] : mode == 'video' ? ['Cinematic product video', 'Travel film', 'Music visualizer', 'Short social video'] : ['Afrobeat song', 'Cinematic soundtrack', 'Chill R&B', 'Energetic pop'];
    return Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Container(width:72,height:72,decoration:BoxDecoration(color:cs.primaryContainer,shape:BoxShape.circle),child:Icon(Icons.auto_awesome_rounded,size:36,color:cs.primary)), const SizedBox(height:20), Text(mode=='chat'?'How can I help you?':'What do you want to create?',style:const TextStyle(fontSize:28,fontWeight:FontWeight.w900),textAlign:TextAlign.center), const SizedBox(height:8), Text('Powered by multiple AI models. Choose a model above and start.', textAlign:TextAlign.center, style:TextStyle(color:cs.onSurfaceVariant)), const SizedBox(height:22), Wrap(spacing:8,runSpacing:8,alignment:WrapAlignment.center,children:[for(final s in suggestions) ActionChip(label:Text(s),onPressed:loading?null:(){prompt.text=s;})]) ])));
  }

  Widget message(Map<String,dynamic> t) { final user=t['role']=='user'; final cs=Theme.of(context).colorScheme; return Padding(padding:EdgeInsets.fromLTRB(user?52:12,8,user?12:52,8),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[if(!user) CircleAvatar(radius:16,backgroundColor:cs.primaryContainer,child:Icon(Icons.auto_awesome,size:16,color:cs.primary)),if(!user) const SizedBox(width:8),Expanded(child:Container(padding:const EdgeInsets.symmetric(horizontal:15,vertical:12),decoration:BoxDecoration(color:user?cs.primaryContainer:cs.surfaceContainerHighest,borderRadius:BorderRadius.circular(20)),child:SelectableText('${t['text']}',style:const TextStyle(fontSize:15.5,height:1.45))))])); }

  Widget media() { final m=resultUrls(); if(m.isEmpty)return const SizedBox.shrink(); return Padding(padding:const EdgeInsets.fromLTRB(44,6,12,18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[if(mode=='image') ClipRRect(borderRadius:BorderRadius.circular(18),child:Image.network(m.first,width:double.infinity,height:300,fit:BoxFit.cover,errorBuilder:(_,__,___)=>const SizedBox(height:150,child:Center(child:Text('Preview unavailable'))))), const SizedBox(height:8),Wrap(spacing:8,runSpacing:8,children:[for(final u in m) FilledButton.tonalIcon(onPressed:()=>openUrl(u),icon:Icon(mode=='video'?Icons.play_arrow:mode=='music'?Icons.headphones:Icons.open_in_new),label:Text(mode=='video'?'Watch':mode=='music'?'Listen':'Open')),for(final u in m) OutlinedButton.icon(onPressed:()=>saveUrl(u),icon:const Icon(Icons.download_rounded),label:const Text('Save'))]) ])); }

  Widget composer() { return SafeArea(child:Padding(padding:const EdgeInsets.fromLTRB(12,6,12,10),child:Column(children:[if(attachments.isNotEmpty)SizedBox(height:38,child:ListView(scrollDirection:Axis.horizontal,children:[for(final f in attachments)Padding(padding:const EdgeInsets.only(right:6),child:Chip(avatar:const Icon(Icons.attach_file,size:16),label:ConstrainedBox(constraints:const BoxConstraints(maxWidth:150),child:Text(f.name,overflow:TextOverflow.ellipsis)),onDeleted:()=>setState(()=>attachments.remove(f))))])),Container(decoration:BoxDecoration(color:Theme.of(context).colorScheme.surfaceContainerHighest,borderRadius:BorderRadius.circular(27),border:Border.all(color:Theme.of(context).dividerColor)),child:Row(crossAxisAlignment:CrossAxisAlignment.end,children:[IconButton(onPressed:loading?null:pickFiles,icon:const Icon(Icons.add_circle_outline_rounded)),Expanded(child:TextField(controller:prompt,enabled:!loading,minLines:1,maxLines:6,textInputAction:TextInputAction.newline,decoration:InputDecoration(hintText:mode=='chat'?'Message GG AI':'Describe what you want…',border:InputBorder.none,contentPadding:const EdgeInsets.symmetric(vertical:14)))),Padding(padding:const EdgeInsets.only(right:7,bottom:5),child:IconButton.filled(onPressed:loading?null:run,icon:Icon(loading?Icons.hourglass_top_rounded:Icons.arrow_upward_rounded))) ]))])); }

  @override Widget build(BuildContext context) { final empty=turns.isEmpty&&result==null&&!loading; return Scaffold(body:Stack(children:[Column(children:[header(),Expanded(child:turns.isEmpty? (empty?welcome():const SizedBox.shrink()):ListView(controller:scroll,padding:const EdgeInsets.only(top:12),children:[for(final t in turns)message(t),if(loading)const Padding(padding:EdgeInsets.fromLTRB(52,10,20,20),child:Row(children:[SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)),SizedBox(width:10),Text('Thinking…')])),if(result!=null&&mode!='chat')media(),if(status.isNotEmpty&&!loading)Padding(padding:const EdgeInsets.fromLTRB(52,0,16,12),child:Text(status,style:const TextStyle(fontSize:12)))])),composer()]),sidePanel()])); }
}

class _ModelPicker extends StatefulWidget { final List<_Model> models; final String selected, mode; const _ModelPicker({required this.models,required this.selected,required this.mode}); @override State<_ModelPicker> createState()=>_ModelPickerState(); }
class _ModelPickerState extends State<_ModelPicker> { String q=''; @override Widget build(BuildContext context){final list=widget.models.where((m)=>'${m.name} ${m.id} ${m.tag}'.toLowerCase().contains(q.toLowerCase())).toList(); return SafeArea(child:Padding(padding:const EdgeInsets.fromLTRB(16,4,16,16),child:Column(mainAxisSize:MainAxisSize.min,children:[const Align(alignment:Alignment.centerLeft,child:Text('Choose model',style:TextStyle(fontSize:22,fontWeight:FontWeight.w900))),const SizedBox(height:10),TextField(onChanged:(v)=>setState(()=>q=v),decoration:InputDecoration(prefixIcon:const Icon(Icons.search),hintText:'Search models',filled:true,border:OutlineInputBorder(borderRadius:BorderRadius.circular(16)))),const SizedBox(height:8),Flexible(child:ListView.builder(shrinkWrap:true,itemCount:list.length,itemBuilder:(_,i){final m=list[i];return ListTile(leading:CircleAvatar(child:Icon(widget.mode=='image'?Icons.image:widget.mode=='video'?Icons.movie:widget.mode=='music'?Icons.music_note:Icons.auto_awesome)),title:Text(m.name,style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('${m.tag} • ${m.id}',maxLines:1,overflow:TextOverflow.ellipsis),trailing:m.id==widget.selected?const Icon(Icons.check_circle):null,onTap:()=>Navigator.pop(context,m.id));}))]));}}
