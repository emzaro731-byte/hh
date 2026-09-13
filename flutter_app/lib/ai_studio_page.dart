import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'ai_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const imageModels = [
  {'id': 'z-image', 'name': 'Z-Image Turbo'},
  {'id': 'seedream/5.0-lite', 'name': 'Seedream 5 Lite'},
  {'id': 'seedream/5.0-pro', 'name': 'Seedream 5 Pro'},
  {'id': 'google/imagen4-fast', 'name': 'Imagen 4 Fast'},
  {'id': 'google/imagen4', 'name': 'Imagen 4'},
  {'id': 'grok-imagine/text-to-image', 'name': 'Grok Imagine'},
  {'id': 'gpt-image-2', 'name': 'GPT Image 2'},
];
const videoModels = [
  {'id': 'wan/2-2-a14b-text-to-video-turbo', 'name': 'Wan 2.2 Turbo'},
  {'id': 'pixverse/v6-text-to-video', 'name': 'PixVerse V6'},
  {'id': 'kling-3.0-omni/text-to-video', 'name': 'Kling 3.0 Omni'},
];
const musicModels = [
  {'id': 'V6_MINI', 'name': 'Suno V6 Mini'},
  {'id': 'V6', 'name': 'Suno V6'},
  {'id': 'V5_5', 'name': 'Suno V5.5'},
];

class AIStudioPage extends StatefulWidget {
  const AIStudioPage({super.key});
  @override
  State<AIStudioPage> createState() => _AIStudioPageState();
}

class _AIStudioPageState extends State<AIStudioPage> {
  String mode = 'chat';
  String plan = 'free';
  String selectedImage = 'z-image';
  String selectedVideo = 'wan/2-2-a14b-text-to-video-turbo';
  String selectedMusic = 'V6_MINI';
  final prompt = TextEditingController();
  bool loading = false;
  String status = '';
  AIGeneration? result;

  bool get premium => {'go', 'plus', 'ultra'}.contains(plan);
  String get selectedModel => mode == 'image' ? selectedImage : mode == 'video' ? selectedVideo : selectedMusic;
  List<Map<String, String>> get models => mode == 'image' ? imageModels : mode == 'video' ? videoModels : musicModels;

  @override
  void initState() {
    super.initState();
    _loadPlan();
  }

  @override
  void dispose() {
    prompt.dispose();
    super.dispose();
  }

  Future<void> _loadPlan() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      final row = await Supabase.instance.client.from('profiles').select('ai_plan').eq('id', user.id).maybeSingle();
      if (!mounted) return;
      setState(() => plan = {'free', 'go', 'plus', 'ultra'}.contains(row?['ai_plan']) ? row!['ai_plan'].toString() : 'free');
    } catch (_) {}
  }

  void _changeMode(String value) {
    setState(() {
      mode = value;
      result = null;
      prompt.clear();
    });
  }

  Future<void> _generate() async {
    final text = prompt.text.trim();
    if (text.isEmpty || loading) return;
    setState(() {
      loading = true;
      result = null;
      status = 'Connecting…';
    });
    try {
      final options = {
        'model': selectedModel,
        'aspectRatio': mode == 'video' ? '16:9' : '1:1',
        'resolution': '1K',
        'duration': 5,
        'quality': '720p',
        'generateAudio': mode == 'video',
      };
      var done = await AIService.generate(mode, text, options);
      if (mode != 'chat') {
        if (done.taskId == null) throw Exception('The AI service did not return a task ID.');
        done = await AIService.waitForResult(mode, done.taskId!, options, (s) {
          if (mounted) setState(() => status = s);
        });
      }
      if (mounted) {
        setState(() {
          result = done;
          status = 'Complete';
        });
      }
      try { await AIService.save(mode, text, done, selectedModel); } catch (_) {}
    } catch (e) {
      if (mounted) setState(() {
        result = AIGeneration(message: e.toString().replaceFirst('Exception: ', ''));
        status = 'Failed';
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Widget _modelPicker() {
    return DropdownButtonFormField<String>(
      value: models.any((m) => m['id'] == selectedModel) ? selectedModel : models.first['id'],
      decoration: InputDecoration(
        labelText: premium ? 'AI Model • Premium' : 'AI Model • Free',
        prefixIcon: const Icon(Icons.auto_awesome),
        border: const OutlineInputBorder(),
      ),
      items: models.map((m) => DropdownMenuItem(value: m['id'], child: Text(m['name']!))).toList(),
      onChanged: loading ? null : (v) {
        if (v == null) return;
        setState(() {
          if (mode == 'image') selectedImage = v;
          if (mode == 'video') selectedVideo = v;
          if (mode == 'music') selectedMusic = v;
        });
      },
    );
  }

  Widget _result() {
    if (result == null) return const SizedBox.shrink();
    if (result!.message != null && result!.url == null && result!.urls.isEmpty) {
      return Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(result!.message!)));
    }
    final urls = result!.urls.isNotEmpty ? result!.urls : (result!.url == null ? <String>[] : [result!.url!]);
    return Column(children: [
      if (mode == 'image' && urls.isNotEmpty)
        ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.network(urls.first, width: double.infinity, height: 330, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(height: 180, child: Center(child: Icon(Icons.broken_image, size: 60))))),
      if (mode == 'chat' && result!.message != null)
        Card(child: Padding(padding: const EdgeInsets.all(18), child: SelectableText(result!.message!))),
      ...urls.map((u) => Padding(padding: const EdgeInsets.only(top: 10), child: SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: () => _open(u), icon: Icon(mode == 'video' ? Icons.play_arrow : Icons.open_in_new), label: Text(mode == 'video' ? 'Open video' : mode == 'music' ? 'Open music' : 'Open image'))))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final title = mode == 'chat' ? 'Ask anything' : mode == 'image' ? 'Create an image' : mode == 'video' ? 'Create a video' : 'Create music';
    return Scaffold(
      appBar: AppBar(title: const Text('GG AI Studio'), actions: [Padding(padding: const EdgeInsets.only(right: 12), child: Chip(label: Text(premium ? 'Premium' : 'Free')))]),
      body: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 4), child: Row(children: [
          for (final item in const [('chat', Icons.chat_bubble_outline, 'Ask'), ('image', Icons.image_outlined, 'Image'), ('video', Icons.movie_outlined, 'Video'), ('music', Icons.music_note_outlined, 'Music')])
            Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: ChoiceChip(label: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(item.$2, size: 17), const SizedBox(width: 4), Text(item.$3)]), selected: mode == item.$1, onSelected: (_) => _changeMode(item.$1))))
        ])),
        Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(mode == 'image' ? 'Describe the image you want GG to create.' : mode == 'video' ? 'Describe the video you want GG to create.' : mode == 'music' ? 'Describe the song, vocals or instrumental you want.' : 'Get answers, create, summarize and more.'),
          const SizedBox(height: 18),
          if (mode != 'chat') _modelPicker(),
          if (mode != 'chat') const SizedBox(height: 14),
          TextField(controller: prompt, minLines: 5, maxLines: 9, textInputAction: TextInputAction.newline, decoration: InputDecoration(hintText: mode == 'image' ? 'A cinematic Nigerian city at night…' : mode == 'video' ? 'A futuristic city flying through clouds…' : mode == 'music' ? 'Afro-fusion song about ambition…' : 'Ask GG AI anything…', border: const OutlineInputBorder(), prefixIcon: const Padding(padding: EdgeInsets.only(bottom: 70), child: Icon(Icons.auto_awesome)))),
          const SizedBox(height: 14),
          SizedBox(height: 54, child: FilledButton.icon(onPressed: loading ? null : _generate, icon: loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome), label: Text(loading ? status : mode == 'chat' ? 'Ask GG AI' : 'Generate ${mode[0].toUpperCase()}${mode.substring(1)}'))),
          if (status.isNotEmpty && !loading) Padding(padding: const EdgeInsets.only(top: 10), child: Center(child: Text(status))),
          const SizedBox(height: 18),
          _result(),
        ])),
      ])),
    );
  }
}
