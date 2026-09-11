import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class AIPage extends StatefulWidget {
  const AIPage({super.key});
  @override
  State<AIPage> createState() => _AIPageState();
}

class _AIPageState extends State<AIPage> {
  final sb = Supabase.instance.client;
  final prompt = TextEditingController();
  String mode = 'chat', model = '', status = '';
  bool loading = false;
  Map<String, dynamic>? result;
  List<dynamic> history = [];

  @override
  void initState() {
    super.initState();
    loadHistory();
  }

  Future<void> loadHistory() async {
    try {
      final d = await sb.from('ai_generations').select('id,type,prompt,model,result_urls,result_text,created_at').order('created_at', ascending: false).limit(20);
      if (mounted) setState(() => history = d);
    } catch (_) {}
  }

  void choose(String x) {
    setState(() {
      mode = x;
      result = null;
      status = '';
      model = x == 'image' ? 'flux-2/flex-text-to-image' : x == 'video' ? 'runway' : x == 'music' ? 'suno' : '';
    });
  }

  Future<void> run() async {
    if (prompt.text.trim().isEmpty || loading) return;
    setState(() => loading = true);
    try {
      final r = await sb.functions.invoke('ai-generate', body: {
        'type': mode,
        'prompt': prompt.text.trim(),
        'options': {'model': model, 'aspectRatio': mode == 'video' ? '9:16' : '1:1', 'duration': 5, 'quality': '720p'}
      });
      var done = Map<String, dynamic>.from(r.data ?? {});
      if (mode != 'chat') {
        final task = done['taskId'];
        if (task == null) throw Exception('No generation task was returned');
        final started = DateTime.now();
        while (DateTime.now().difference(started) < const Duration(minutes: 15)) {
          await Future.delayed(const Duration(seconds: 3));
          final s = await sb.functions.invoke('ai-generate', body: {'action': 'status', 'type': mode, 'taskId': task});
          done = Map<String, dynamic>.from(s.data ?? {});
          if (mounted) setState(() => status = done['status']?.toString() ?? 'Generating...');
          final state = (done['status'] ?? '').toString().toLowerCase();
          if (done['url'] != null || (done['urls'] is List && done['urls'].isNotEmpty) || ['success', 'succeeded', 'complete', 'completed'].contains(state)) break;
        }
      }
      await sb.functions.invoke('ai-save', body: {
        'type': mode,
        'prompt': prompt.text.trim(),
        'model': model,
        'taskId': done['taskId'],
        'urls': done['urls'] ?? (done['url'] != null ? [done['url']] : []),
        'resultText': done['message']
      });
      if (mounted) setState(() => result = done);
      await loadHistory();
    } catch (e) {
      if (mounted) setState(() => result = {'message': e.toString()});
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    return Scaffold(
      appBar: AppBar(title: const Text('GG AI Studio', style: TextStyle(fontWeight: FontWeight.w900))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final x in ['chat', 'image', 'video', 'music'])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(label: Text(x[0].toUpperCase() + x.substring(1)), selected: mode == x, onSelected: (_) => choose(x)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(mode == 'chat' ? 'Ask GG AI anything' : 'Describe your $mode', style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            TextField(controller: prompt, minLines: 6, maxLines: 10, decoration: InputDecoration(hintText: 'Describe what you want...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)))),
            if (mode != 'chat') Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('Model: $model')),
            SizedBox(width: double.infinity, height: 52, child: FilledButton(onPressed: loading ? null : run, child: Text(loading ? 'Creating...' : mode == 'chat' ? 'Ask GG AI' : 'Generate $mode'))),
            if (status.isNotEmpty) Padding(padding: const EdgeInsets.all(12), child: Text(status)),
            if (result?['message'] != null) Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(result!['message'].toString()))),
            if (result?['url'] != null) Padding(padding: const EdgeInsets.only(top: 12), child: FilledButton(onPressed: () => launchUrl(Uri.parse(result!['url'].toString())), child: Text('Open $mode'))),
            if (history.isNotEmpty) ...[
              const SizedBox(height: 25),
              const Text('Generation history', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              for (final h in history)
                ListTile(
                  leading: Text(h['type'] == 'chat' ? '🤖' : h['type'] == 'image' ? '🖼️' : h['type'] == 'video' ? '🎬' : '🎵', style: const TextStyle(fontSize: 24)),
                  title: Text(h['prompt'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(h['created_at'] ?? ''),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
