import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const List<Map<String, String>> kieFreeImageModels = [
  {'id': 'z-image', 'name': 'Z-Image Turbo', 'description': 'Free / trial image model'},
];

const List<Map<String, String>> kiePremiumImageModels = [
  {'id': 'google/nano-banana-2', 'name': 'Nano Banana 2', 'description': 'Premium fast image generation'},
  {'id': 'seedream/5.0-pro', 'name': 'Seedream 5 Pro', 'description': 'Premium expert image generation'},
  {'id': 'google/imagen4', 'name': 'Imagen 4', 'description': 'Premium quality image generation'},
  {'id': 'google/nano-banana-pro', 'name': 'Nano Banana Pro', 'description': 'Premium expert image generation'},
  {'id': 'flux-2/pro-text-to-image', 'name': 'Flux 2 Pro', 'description': 'Premium quality image generation'},
  {'id': 'grok-imagine/text-to-image', 'name': 'Grok Imagine', 'description': 'Premium creative image generation'},
  {'id': 'gpt-image-2', 'name': 'GPT Image 2', 'description': 'Premium quality image generation'},
];

const List<Map<String, String>> kieFreeVideoModels = [
  {'id': 'wan/2-2-a14b-text-to-video-turbo', 'name': 'Wan 2.2 A14B Turbo', 'description': 'Free / trial video model'},
];

const List<Map<String, String>> kiePremiumVideoModels = [
  {'id': 'pixverse/v6-text-to-video', 'name': 'PixVerse V6', 'description': 'Premium fast video generation'},
  {'id': 'kling-3.0-omni/text-to-video', 'name': 'Kling 3.0 Omni', 'description': 'Premium expert video generation'},
  {'id': 'wan/2-7-text-to-video', 'name': 'Wan 2.7', 'description': 'Premium video generation'},
];

class AIStudioPage extends StatefulWidget {
  const AIStudioPage({super.key});
  @override
  State<AIStudioPage> createState() => _AIStudioPageState();
}

class _AIStudioPageState extends State<AIStudioPage> {
  String mode = 'chat';
  String plan = 'free';
  String selectedImageModel = 'z-image';
  String selectedVideoModel = 'wan/2-2-a14b-text-to-video-turbo';
  bool loadingPlan = true;

  bool get isPremium => plan == 'go' || plan == 'plus' || plan == 'ultra';

  List<Map<String, String>> get imageModels =>
      isPremium ? [...kieFreeImageModels, ...kiePremiumImageModels] : kieFreeImageModels;

  List<Map<String, String>> get videoModels =>
      isPremium ? [...kieFreeVideoModels, ...kiePremiumVideoModels] : kieFreeVideoModels;

  @override
  void initState() {
    super.initState();
    _loadPlan();
  }

  Future<void> _loadPlan() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      final row = await Supabase.instance.client
          .from('profiles')
          .select('ai_plan')
          .eq('id', user.id)
          .maybeSingle();
      final next = (row?['ai_plan'] ?? 'free').toString();
      if (!mounted) return;
      setState(() {
        plan = {'free', 'go', 'plus', 'ultra'}.contains(next) ? next : 'free';
        loadingPlan = false;
        selectedImageModel = 'z-image';
        selectedVideoModel = 'wan/2-2-a14b-text-to-video-turbo';
      });
    } catch (_) {
      if (mounted) setState(() => loadingPlan = false);
    }
  }

  String get planLabel {
    if (plan == 'go') return 'Go Premium';
    if (plan == 'plus') return 'Plus Premium';
    if (plan == 'ultra') return 'Ultra Premium';
    return 'Free';
  }

  Widget _modelPicker({required bool image}) {
    final models = image ? imageModels : videoModels;
    final selected = image ? selectedImageModel : selectedVideoModel;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DropdownButtonFormField<String>(
        value: models.any((m) => m['id'] == selected) ? selected : models.first['id'],
        decoration: InputDecoration(
          labelText: isPremium
              ? 'KIE ${image ? 'Image' : 'Video'} Model • $planLabel'
              : 'KIE Free / Trial ${image ? 'Image' : 'Video'} Model',
          prefixIcon: Icon(isPremium ? Icons.workspace_premium : Icons.lock_open),
          border: const OutlineInputBorder(),
        ),
        items: models.map((m) {
          final premium = m['id'] != (image ? 'z-image' : 'wan/2-2-a14b-text-to-video-turbo');
          return DropdownMenuItem<String>(
            value: m['id'],
            child: Row(
              children: [
                Expanded(child: Text(m['name']!)),
                if (premium) const Icon(Icons.workspace_premium, size: 17),
              ],
            ),
          );
        }).toList(),
        onChanged: loadingPlan
            ? null
            : (v) {
                if (v == null) return;
                setState(() {
                  if (image) {
                    selectedImageModel = v;
                  } else {
                    selectedVideoModel = v;
                  }
                });
              },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Studio'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Chip(
                avatar: Icon(
                  isPremium ? Icons.workspace_premium : Icons.auto_awesome,
                  size: 17,
                ),
                label: Text(planLabel),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          if (mode == 'image') _modelPicker(image: true),
          if (mode == 'video') _modelPicker(image: false),
          if (!isPremium && (mode == 'image' || mode == 'video'))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Card(
                child: ListTile(
                  leading: const Icon(Icons.workspace_premium),
                  title: const Text('Unlock stronger KIE models'),
                  subtitle: const Text('Premium plans can select the advanced image and video models.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Upgrade to a Premium plan to unlock stronger KIE models.')),
                  ),
                ),
              ),
            ),
          Expanded(
            child: Center(
              child: Text(
                mode == 'image'
                    ? 'Image: $selectedImageModel'
                    : mode == 'video'
                        ? 'Video: $selectedVideoModel'
                        : 'AI Studio • $planLabel',
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
