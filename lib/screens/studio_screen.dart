import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ai_service.dart';

class StudioScreen extends StatefulWidget {
  final SharedPreferences prefs;

  const StudioScreen({super.key, required this.prefs});

  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends State<StudioScreen> {
  int tab = 0;
  final prompt = TextEditingController();
  final service = const AiService();
  final messages = <Map<String, String>>[];
  String? result;
  bool busy = false;
  bool webSearch = true;

  final tabs = const [
    (Icons.chat_bubble_outline, 'Chat'),
    (Icons.image_outlined, 'Image'),
    (Icons.music_note_outlined, 'Music'),
    (Icons.movie_outlined, 'Video'),
  ];

  @override
  void dispose() {
    prompt.dispose();
    super.dispose();
  }

  Future<void> run() async {
    final text = prompt.text.trim();
    if (text.isEmpty || busy) {
      return;
    }

    setState(() {
      busy = true;
      result = null;
    });

    try {
      if (tab == 0) {
        messages.add({'role': 'user', 'content': text});
        final answer = await service.chat(messages: messages);
        messages.add({'role': 'assistant', 'content': answer});
        result = answer;
      } else if (tab == 1) {
        if (webSearch) {
          result = 'Searching the web and creating image...';
          if (mounted) setState(() {});
        }
        result = 'Image job: ${await service.generateImage(text, webSearch: webSearch)}';
      } else if (tab == 2) {
        result = 'Music job: ${await service.generateMusic(text)}';
      } else {
        if (webSearch) {
          result = 'Searching the web and creating video...';
          if (mounted) setState(() {});
        }
        result = 'Video job: ${await service.generateVideo(text, webSearch: webSearch)}';
      }
      prompt.clear();
    } catch (e) {
      result = 'Generation error: $e';
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedTitle = tabs[tab].$2;
    final canSearch = tab == 0 || tab == 1 || tab == 3;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.auto_awesome),
            SizedBox(width: 10),
            Text('VEYLOLA', style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () {
              setState(() {
                result = null;
                messages.clear();
              });
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Create anything with AI',
                  style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            SizedBox(
              height: 58,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: tabs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  return ChoiceChip(
                    selected: tab == i,
                    onSelected: (_) {
                      setState(() {
                        tab = i;
                        result = null;
                      });
                    },
                    avatar: Icon(tabs[i].$1, size: 18),
                    label: Text(tabs[i].$2),
                  );
                },
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white12),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF11162A), Color(0xFF0C0F1A)],
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selectedTitle,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            tab == 0
                                ? 'Ask VEYLOLA anything and use live web information.'
                                : 'Describe what you want to create.',
                            style: const TextStyle(color: Colors.white60),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: prompt,
                            minLines: 5,
                            maxLines: 9,
                            decoration: InputDecoration(
                              hintText: tab == 0
                                  ? 'Write a message...'
                                  : 'Example: A cinematic futuristic Nigerian city at night...',
                              filled: true,
                              fillColor: Colors.black26,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          if (canSearch) ...[
                            const SizedBox(height: 10),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(.04),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: SwitchListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                                value: webSearch,
                                onChanged: (value) => setState(() => webSearch = value),
                                secondary: const Icon(Icons.language),
                                title: const Text('Live web research'),
                                subtitle: Text(
                                  tab == 0
                                      ? 'Use current web information for answers'
                                      : 'Research current facts before creating',
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          SizedBox(
                            height: 52,
                            child: FilledButton.icon(
                              onPressed: busy ? null : run,
                              icon: busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.auto_awesome),
                              label: Text(busy ? 'Creating...' : 'Generate'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (result != null) ...[
                      const SizedBox(height: 18),
                      const Text(
                        'Result',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(.05),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: SelectableText(result!),
                      ),
                    ],
                    const SizedBox(height: 28),
                    const Text(
                      'What you can create',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    const SizedBox(height: 12),
                    const Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _Feature(icon: Icons.chat_bubble, text: 'Smart chat'),
                        _Feature(icon: Icons.language, text: 'Web search'),
                        _Feature(icon: Icons.image, text: 'Images'),
                        _Feature(icon: Icons.music_note, text: 'Music'),
                        _Feature(icon: Icons.movie, text: 'Videos'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Feature({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 17),
      label: Text(text),
    );
  }
}
