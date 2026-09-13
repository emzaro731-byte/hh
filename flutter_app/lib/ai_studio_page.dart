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
      final data = await sb.from('ai_generations').select('id,type,prompt,model,result_urls,result_text,created_at').order('created_at', ascending: false).limit(40);
      if (mounted) setState(() => history = List<dynamic>.from(data));
    } catch (_) {}
  }

  void newChat() {
    setState(() { turns.clear(); result = null; status = ''; prompt.clear(); attachments.clear(); });
    if (menuOpen) setState(() => menuOpen = false);
  }

  void selectMode(String value) {
    setState(() { mode = value; model = modelsFor(value).first.id; result = null; status = ''; });
  }

  List<_Model> modelsFor(String value) => value == 'chat' ? chatModels : value == 'image' ? imageModels : value == 'video' ? videoModels : musicModels;

  Future<void> chooseModel() async {
    final picked = await showModalBottomSheet<String>(context: context, showDragHandle: true, isScrollControlled: true, builder: (_) => _ModelPicker(models: models, selected: model, mode: mode));
    if (picked != null && mounted) setState(() => model = picked);
  }

  Future<void> pickFiles() async {
    final picked = await FilePicker.platform.pickFiles(allowMultiple: true, withData: false);
    if (picked != null && mounted) setState(() => attachments = picked.files);
  }

  Future<void> run() async {
    final text = prompt.text.trim();
    if (text.isEmpty || loading) return;
    setState(() { loading = true; status = mode == 'chat' ? 'Thinking…' : 'Creating…'; result = null; turns.add({'role': 'user', 'text': text}); });
    prompt.clear();
    await Future.delayed(const Duration(milliseconds: 80));
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
      if (mounted) {
        setState(() { result = done; status = 'Complete'; if (mode == 'chat' && done['message'] != null) turns.add({'role': 'assistant', 'text': done['message'].toString()}); });
        _scrollBottom();
      }
      await loadHistory();
    } catch (e) {
      if (mounted) { setState(() { status = 'Failed'; result = {'message': e.toString()}; turns.add({'role': 'assistant', 'text': 'Sorry, something went wrong. $e'}); }); _scrollBottom(); }
    } finally { if (mounted) setState(() => loading = false); }
  }

  void _scrollBottom() { WidgetsBinding.instance.addPostFrameCallback((_) { if (scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut); }); }

  List<String> urls(dynamic value) {
    if (value is List) return value.where((x) => x != null && '$x'.isNotEmpty).map((x) => '$x').toList();
    if (value is String && value.isNotEmpty) return [value];
    return [];
  }
  List<String> resultUrls() => result == null ? [] : (() { final a = urls(result!['urls']); if (a.isNotEmpty) return a; final b = urls(result!['result_urls']); if (b.isNotEmpty) return b; return urls(result!['url']); })();
  IconData modeIcon(String v) => v == 'image' ? Icons.image_outlined : v == 'video' ? Icons.movie_creation_outlined : v == 'music' ? Icons.music_note_rounded : Icons.auto_awesome;
  String label(String v) => v[0].toUpperCase() + v.substring(1);

  Future<void> openUrl(String url) async { await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication); }
  String extFor(String type, String url) { final p = url.split('?').first; final i = p.lastIndexOf('.'); if (i > 0 && p.length - i <= 6) return p.substring(i + 1); return type == 'video' ? 'mp4' : type == 'music' ? 'mp3' : 'jpg'; }
  Future<void> saveUrl(String url) async {
    try {
      final client = HttpClient(); final req = await client.getUrl(Uri.parse(url)); final res = await req.close();
      final bytes = BytesBuilder(); await for (final c in res) { bytes.add(c); }
      final saved = await FilePicker.platform.saveFile(fileName: 'gg_ai_${DateTime.now().millisecondsSinceEpoch}.${extFor(mode, url)}', bytes: Uint8List.fromList(bytes.takeBytes()));
      if (mounted && saved != null) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved successfully')));
      client.close(force: true);
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e'))); }
  }

  Widget topBar() => SafeArea(child: Container(height: 62, padding: const EdgeInsets.symmetric(horizontal: 12), decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: .25)))), child: Row(children: [IconButton(onPressed: () => setState(() => menuOpen = !menuOpen), icon: const Icon(Icons.menu_rounded)), const SizedBox(width: 2), Expanded(child: GestureDetector(onTap: chooseModel, child: Row(children: [const Text('GG AI', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)), const SizedBox(width: 7), Flexible(child: Text(selected.name, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant))), const Icon(Icons.keyboard_arrow_down_rounded, size: 19)]))), IconButton(onPressed: newChat, tooltip: 'New chat', icon: const Icon(Icons.edit_square_rounded))]));

  Widget drawer() => AnimatedPositioned(duration: const Duration(milliseconds: 220), left: menuOpen ? 0 : -300, top: 0, bottom: 0, child: Material(elevation: 20, child: SafeArea(child: SizedBox(width: 292, child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [Row(children: [const Expanded(child: Text('GG AI Studio', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900))), IconButton(onPressed: () => setState(() => menuOpen = false), icon: const Icon(Icons.close))]), const SizedBox(height: 8), FilledButton.icon(onPressed: newChat, style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48)), icon: const Icon(Icons.add), label: const Text('New chat')), const SizedBox(height: 12), const Align(alignment: Alignment.centerLeft, child: Text('Modes', style: TextStyle(fontWeight: FontWeight.w800))), const SizedBox(height: 6), for (final v in ['chat','image','video','music']) ListTile(leading: Icon(modeIcon(v)), title: Text(label(v)), selected: mode == v, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), onTap: () { selectMode(v); setState(() => menuOpen = false); }), const Divider(), const Align(alignment: Alignment.centerLeft, child: Text('Recent creations', style: TextStyle(fontWeight: FontWeight.w800))), const SizedBox(height: 4), Expanded(child: ListView.builder(itemCount: history.length, itemBuilder: (_, i) { final h = history[i]; return ListTile(dense: true, leading: Icon(modeIcon('${h['type'] ?? 'chat'}'), size: 18), title: Text('${h['prompt'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis), onTap: () => setState(() => menuOpen = false)); }))]))))));

  Widget composer() => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 10), child: Column(children: [if (attachments.isNotEmpty) SizedBox(height: 36, child: ListView(scrollDirection: Axis.horizontal, children: [for (final f in attachments) Padding(padding: const EdgeInsets.only(right: 6), child: Chip(avatar: const Icon(Icons.attach_file, size: 16), label: Text(f.name, overflow: TextOverflow.ellipsis), onDeleted: () => setState(() => attachments.remove(f))))])), Container(decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(24), color: Theme.of(context).colorScheme.surfaceContainerHighest), child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [IconButton(onPressed: loading ? null : pickFiles, icon: const Icon(Icons.add_circle_outline)), Expanded(child: TextField(controller: prompt, enabled: !loading, minLines: 1, maxLines: 6, textInputAction: TextInputAction.newline, decoration: const InputDecoration(hintText: 'Message GG AI', border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 13)))), IconButton(onPressed: loading ? null : run, icon: CircleAvatar(radius: 17, child: Icon(loading ? Icons.stop_rounded : Icons.arrow_upward_rounded, size: 19))) ]))]));

  Widget mediaResult() { final media = resultUrls(); if (media.isEmpty) return const SizedBox.shrink(); return Padding(padding: const EdgeInsets.fromLTRB(52, 4, 16, 18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [if (mode == 'image') ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.network(media.first, width: double.infinity, height: 300, fit: BoxFit.cover)), Wrap(spacing: 8, children: [for (final u in media) FilledButton.tonalIcon(onPressed: () => openUrl(u), icon: Icon(mode == 'video' ? Icons.play_arrow : mode == 'music' ? Icons.headphones : Icons.open_in_new), label: Text(mode == 'video' ? 'Watch' : mode == 'music' ? 'Listen' : 'Open')), for (final u in media) OutlinedButton.icon(onPressed: () => saveUrl(u), icon: const Icon(Icons.download_rounded), label: const Text('Save'))]) ])); }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(body: Stack(children: [Column(children: [topBar(), Expanded(child: turns.isEmpty && result == null ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [CircleAvatar(radius: 34, backgroundColor: cs.primaryContainer, child: Icon(Icons.auto_awesome, size: 32, color: cs.primary)), const SizedBox(height: 18), const Text('How can I help you?', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)), const SizedBox(height: 8), Text('Ask anything, create images, generate video or make music.', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)), const SizedBox(height: 20), Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [for (final s in ['Explain something','Create an image','Generate a video','Make music']) ActionChip(label: Text(s), onPressed: () { if (s.contains('image')) selectMode('image'); else if (s.contains('video')) selectMode('video'); else if (s.contains('music')) selectMode('music'); prompt.text = s == 'Explain something' ? 'Explain something clearly for me.' : ''; })]) ]))) : ListView.builder(controller: scroll, padding: const EdgeInsets.fromLTRB(0, 12, 0, 8), itemCount: turns.length, itemBuilder: (_, i) { final t = turns[i]; final user = t['role'] == 'user'; return Padding(padding: EdgeInsets.fromLTRB(user ? 48 : 16, 8, user ? 16 : 48, 8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: user ? MainAxisAlignment.end : MainAxisAlignment.start, children: [if (!user) Padding(padding: const EdgeInsets.only(right: 10, top: 2), child: CircleAvatar(radius: 15, backgroundColor: cs.primaryContainer, child: Icon(Icons.auto_awesome, size: 16, color: cs.primary)), Flexible(child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11), decoration: BoxDecoration(color: user ? cs.primaryContainer : Colors.transparent, borderRadius: BorderRadius.circular(18)), child: Text('${t['text']}', style: const TextStyle(fontSize: 16, height: 1.45)))) ])); }),), if (result != null && mode != 'chat') mediaResult(), composer()]), if (menuOpen) Positioned.fill(child: GestureDetector(onTap: () => setState(() => menuOpen = false), child: Container(color: Colors.black.withValues(alpha: .18)))), drawer() ]));
  }
}

class _ModelPicker extends StatefulWidget {
  final List<_Model> models; final String selected; final String mode;
  const _ModelPicker({required this.models, required this.selected, required this.mode});
  @override State<_ModelPicker> createState() => _ModelPickerState();
}
class _ModelPickerState extends State<_ModelPicker> {
  String query = '';
  @override Widget build(BuildContext context) { final list = widget.models.where((m) => '${m.name} ${m.id} ${m.tag}'.toLowerCase().contains(query.toLowerCase())).toList(); return SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), child: Column(mainAxisSize: MainAxisSize.min, children: [const Text('Choose a model', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)), const SizedBox(height: 10), TextField(onChanged: (v) => setState(() => query = v), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search models…')), const SizedBox(height: 8), Flexible(child: ListView.builder(shrinkWrap: true, itemCount: list.length, itemBuilder: (_, i) { final m = list[i]; return ListTile(leading: CircleAvatar(child: Icon(widget.mode == 'image' ? Icons.image : widget.mode == 'video' ? Icons.movie : widget.mode == 'music' ? Icons.music_note : Icons.auto_awesome)), title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text('${m.tag} • ${m.id}', maxLines: 1, overflow: TextOverflow.ellipsis), trailing: m.id == widget.selected ? const Icon(Icons.check_circle) : null, onTap: () => Navigator.pop(context, m.id)); }))]))); }
}
