import 'package:flutter/material.dart';

// KIE-supported video models used by the AI Studio video picker.
// Keep model IDs aligned with the KIE backend/Edge Function.
const List<Map<String, String>> kieFreeVideoModels = [
  {
    'id': 'wan/2-2-a14b-turbo',
    'name': 'Wan 2.2 A14B Turbo',
    'description': 'Fast KIE video model for free/trial mode',
  },
  {
    'id': 'wan/2-6-text-to-video',
    'name': 'Wan 2.6',
    'description': 'KIE text-to-video',
  },
  {
    'id': 'kling/v2.1-standard',
    'name': 'Kling 2.1 Standard',
    'description': 'KIE video generation',
  },
  {
    'id': 'bytedance/v1-lite',
    'name': 'ByteDance V1 Lite',
    'description': 'Fast/lower-cost KIE video option',
  },
];

class AIStudioPage extends StatefulWidget {
  const AIStudioPage({super.key});
  @override
  State<AIStudioPage> createState() => _AIStudioPageState();
}

class _AIStudioPageState extends State<AIStudioPage> {
  String mode = 'chat';
  String selectedVideoModel = kieFreeVideoModels.first['id']!;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Studio')),
      body: Column(
        children: [
          const SizedBox(height: 12),
          if (mode == 'video')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DropdownButtonFormField<String>(
                value: selectedVideoModel,
                decoration: const InputDecoration(
                  labelText: 'KIE Free / Trial Video Model',
                  border: OutlineInputBorder(),
                ),
                items: kieFreeVideoModels
                    .map((m) => DropdownMenuItem<String>(
                          value: m['id'],
                          child: Text(m['name']!),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => selectedVideoModel = v);
                },
              ),
            ),
          Expanded(
            child: Center(
              child: Text(
                mode == 'video'
                    ? 'Selected: $selectedVideoModel'
                    : 'AI Studio',
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: ['chat', 'image', 'video', 'music'].indexOf(mode),
        onDestinationSelected: (i) => setState(() {
          mode = ['chat', 'image', 'video', 'music'][i];
        }),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'Chat'),
          NavigationDestination(icon: Icon(Icons.image_outlined), label: 'Image'),
          NavigationDestination(icon: Icon(Icons.movie_outlined), label: 'Video'),
          NavigationDestination(icon: Icon(Icons.music_note_outlined), label: 'Music'),
        ],
      ),
    );
  }
}
