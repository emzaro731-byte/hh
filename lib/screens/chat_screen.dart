import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../services/ai_service.dart';

class ChatScreen extends StatefulWidget {
  final SharedPreferences prefs;
  const ChatScreen({super.key, required this.prefs});
  @override State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _uuid = const Uuid();
  const _ai = AiService();
  List<Map<String, String>> _messages = [];
  bool _busy = false;
  bool _menuOpen = false;
  String _tool = 'Chat';
  String _model = 'GPT-OSS 120B';
  String _mode = 'Fast';

  final _tools = const [
    {'name': 'Chat', 'icon': Icons.chat_bubble_outline, 'hint': 'Ask anything'},
    {'name': 'Image', 'icon': Icons.image_outlined, 'hint': 'Generate images'},
    {'name': 'Music', 'icon': Icons.music_note_outlined, 'hint': 'Create music'},
    {'name': 'Video', 'icon': Icons.movie_outlined, 'hint': 'Generate videos'},
  ];

  final _models = const [
    {'name': 'GPT-OSS 120B', 'desc': 'Advanced reasoning', 'model': 'openai/gpt-oss-120b'},
    {'name': 'GPT-OSS 20B', 'desc': 'Very fast', 'model': 'openai/gpt-oss-20b'},
    {'name': 'Qwen 3.6 27B', 'desc': 'Strong all-rounder', 'model': 'qwen/qwen3.6-27b'},
    {'name': 'Compound', 'desc': 'AI system with tools', 'model': 'groq/compound'},
  ];
  String get _modelId => _models.firstWhere((m) => m['name'] == _model)['model']!;

  @override
  void initState() {
    super.initState();
    final saved = widget.prefs.getString('messages');
    if (saved != null) {
      try { _messages = List<Map<String, String>>.from((jsonDecode(saved) as List).map((e) => Map<String, String>.from(e))); } catch (_) {}
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;
    _controller.clear();
    if (_tool == 'Image') return _media(false, text);
    if (_tool == 'Video') return _media(true, text);
    if (_tool == 'Music') return _sendMusic(text);
    setState(() { _messages.add({'role': 'user', 'content': text, 'id': _uuid.v4()}); _busy = true; });
    await _save();
    try {
      final prompt = _mode == 'Fast' ? text : '$_mode mode: $text';
      final history = [..._messages];
      history[history.length - 1] = {'role': 'user', 'content': prompt};
      final reply = await _ai.chat(messages: history.map((m) => {'role': m['role']!, 'content': m['content']!}).toList(), model: _modelId);
      setState(() => _messages.add({'role': 'assistant', 'content': reply, 'id': _uuid.v4()}));
      await _save();
    } catch (e) { _error(e); }
    finally { if (mounted) setState(() => _busy = false); _jump(); }
  }

  Future<void> _sendMusic(String prompt) async {
    setState(() { _messages.add({'role': 'user', 'content': 'Create music: $prompt', 'id': _uuid.v4()}); _busy = true; });
    try {
      final reply = await _ai.chat(messages: [
        {'role': 'system', 'content': 'You are VEYLORA Music Studio. Write a complete original song concept with title, genre, BPM, structure, lyrics and production direction. Never copy existing lyrics.'},
        {'role': 'user', 'content': prompt},
      ], model: _modelId);
      setState(() => _messages.add({'role': 'assistant', 'content': '🎵 MUSIC BLUEPRINT\n\n$reply', 'id': _uuid.v4()}));
      await _save();
    } catch (e) { _error(e); }
    finally { if (mounted) setState(() => _busy = false); _jump(); }
  }

  Future<void> _media(bool video, String prompt) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final task = video ? await _ai.generateVideo(prompt) : await _ai.generateImage(prompt);
      setState(() => _messages.add({'role': 'assistant', 'content': '✨ VEYLORA ${video ? 'VIDEO' : 'IMAGE'}\n\nGeneration started.\nPrompt: $prompt\nTask ID: $task', 'id': _uuid.v4()}));
      await _save();
    } catch (e) { _error(e); }
    finally { if (mounted) setState(() => _busy = false); _jump(); }
  }

  void _quick(String text) { _controller.text = text; _controller.selection = TextSelection.collapsed(offset: text.length); }
  void _error(Object e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), behavior: SnackBarBehavior.floating)); }
  Future<void> _save() async => widget.prefs.setString('messages', jsonEncode(_messages));
  void _jump() => WidgetsBinding.instance.addPostFrameCallback((_) { if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut); });

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF070A10),
    body: Stack(children: [
      SafeArea(child: Column(children: [
        _header(),
        Expanded(child: _messages.isEmpty ? _welcome() : ListView.builder(controller: _scroll, padding: const EdgeInsets.fromLTRB(16, 12, 16, 18), itemCount: _messages.length, itemBuilder: (c, i) => _bubble(_messages[i]))),
        if (_busy) const Padding(padding: EdgeInsets.only(bottom: 7), child: Text('VEYLORA is working…', style: TextStyle(color: Colors.white54, fontSize: 12))),
        _composer(),
      ])),
      if (_menuOpen) _profileMenu(),
    ]),
  );

  Widget _header() => Padding(padding: const EdgeInsets.fromLTRB(16, 10, 14, 6), child: Column(children: [
    Row(children: [
      IconButton(onPressed: () => setState(() => _menuOpen = !_menuOpen), icon: const Icon(Icons.menu_rounded, size: 31)),
      const Spacer(),
      const Column(children: [Text('VEYLORA AI', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)), Text('One AI • Infinite Possibilities', style: TextStyle(fontSize: 10, color: Colors.white54))]),
      const Spacer(),
      Container(padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8), decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFF6D7CFF))), child: const Row(children: [Icon(Icons.workspace_premium, size: 16), SizedBox(width: 5), Text('Pro', style: TextStyle(fontWeight: FontWeight.bold))])),
    ]),
    const SizedBox(height: 8),
    Row(children: [Expanded(child: Container(height: 52, decoration: BoxDecoration(color: const Color(0xFF11151F), borderRadius: BorderRadius.circular(17), border: Border.all(color: const Color(0xFF27304A))), child: const Center(child: Text('Ask', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))))), const SizedBox(width: 12), const Icon(Icons.history_rounded, color: Colors.white70), const SizedBox(width: 22), const Icon(Icons.folder_outlined, color: Colors.white70), const SizedBox(width: 8)],),
  ]));

  Widget _welcome() => SingleChildScrollView(child: Padding(padding: const EdgeInsets.fromLTRB(18, 25, 18, 18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('Hello, I’m', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
    const Text('VEYLORA AI', style: TextStyle(fontSize: 39, fontWeight: FontWeight.w900, letterSpacing: -1.2)),
    const Text('Chat, create images, make music, produce videos — all in one place.', style: TextStyle(color: Colors.white60, fontSize: 15, height: 1.45)),
    const SizedBox(height: 20),
    Row(children: _tools.map((t) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: _toolCard(t)))).toList()),
    const SizedBox(height: 15),
    Wrap(spacing: 9, runSpacing: 9, children: [
      _idea('Give me creative ideas', Icons.lightbulb_outline, 'Give me 10 powerful creative ideas.'),
      _idea('Create a logo for my brand', Icons.image_outlined, 'Create a premium logo concept for my brand.'),
      _idea('Make a trending Afrobeat song', Icons.music_note_outlined, 'Make a fresh original Afrobeat song concept.'),
      _idea('Generate a cinematic video', Icons.movie_outlined, 'Generate a cinematic futuristic video.'),
    ]),
  ]));

  Widget _toolCard(Map<String, Object> t) => GestureDetector(onTap: () => setState(() => _tool = t['name'] as String), child: Container(padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 4), decoration: BoxDecoration(color: const Color(0xFF101621), borderRadius: BorderRadius.circular(18), border: Border.all(color: _tool == t['name'] ? const Color(0xFF4C8DFF) : const Color(0xFF242B3A))), child: Column(children: [Icon(t['icon'] as IconData, size: 28, color: const Color(0xFF6F9DFF)), const SizedBox(height: 7), Text(t['name'] as String, style: const TextStyle(fontWeight: FontWeight.w800)), Text(t['hint'] as String, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9, color: Colors.white54))])));
  Widget _idea(String label, IconData icon, String text) => ActionChip(avatar: Icon(icon, size: 18), label: Text(label), onPressed: () => _quick(text));

  Widget _bubble(Map<String, String> m) { final user = m['role'] == 'user'; return Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: user ? MainAxisAlignment.end : MainAxisAlignment.start, children: [if (!user) const Padding(padding: EdgeInsets.only(right: 8), child: CircleAvatar(radius: 15, backgroundColor: Color(0xFF222947), child: Icon(Icons.auto_awesome, size: 15, color: Color(0xFF9C83FF))), Flexible(child: GestureDetector(onLongPress: () { Clipboard.setData(ClipboardData(text: m['content'] ?? '')); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard'), behavior: SnackBarBehavior.floating)); }, child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13), decoration: BoxDecoration(color: user ? const Color(0xFF4B3BB2) : const Color(0xFF141925), borderRadius: BorderRadius.circular(20).copyWith(bottomRight: user ? const Radius.circular(5) : null, bottomLeft: user ? null : const Radius.circular(5))), child: Text(m['content'] ?? '', style: const TextStyle(fontSize: 15.5, height: 1.45)))))])); }

  Widget _composer() => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 10), child: Container(padding: const EdgeInsets.fromLTRB(14, 10, 10, 9), decoration: BoxDecoration(color: const Color(0xFF121722), borderRadius: BorderRadius.circular(27), border: Border.all(color: const Color(0xFF303848))), child: Column(children: [TextField(controller: _controller, maxLines: 4, minLines: 1, decoration: const InputDecoration(hintText: 'Ask anything…', border: InputBorder.none, isDense: true)), const SizedBox(height: 7), Row(children: [IconButton(onPressed: () {}, icon: const Icon(Icons.add_circle_outline, size: 28)), _selector(_mode, Icons.bolt, true, _showModes), _selector(_model, Icons.auto_awesome, false, _showModels), IconButton(onPressed: () {}, icon: const Icon(Icons.mic_none_rounded, size: 25)), const Spacer(), GestureDetector(onTap: _busy ? null : _send, child: Container(padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 13), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(23)), child: const Row(children: [Icon(Icons.graphic_eq, color: Colors.black), SizedBox(width: 6), Text('Speak', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800))])))])] )));

  Widget _selector(String text, IconData icon, bool green, VoidCallback tap) => GestureDetector(onTap: tap, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: green ? const Color(0xFF596277) : const Color(0xFF22E878), width: green ? 1 : 1.5)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 18), const SizedBox(width: 5), ConstrainedBox(constraints: const BoxConstraints(maxWidth: 105), child: Text(text, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))), const Icon(Icons.keyboard_arrow_down, size: 18)])));

  void _showModes() { showModalBottomSheet(context: context, backgroundColor: const Color(0xFF121722), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))), builder: (_) => Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Choose tool', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)), const SizedBox(height: 14), ..._tools.map((t) => ListTile(leading: Icon(t['icon'] as IconData), title: Text(t['name'] as String, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(t['hint'] as String), trailing: _tool == t['name'] ? const Icon(Icons.check, color: Color(0xFF22E878)) : null, onTap: () { setState(() => _tool = t['name'] as String); Navigator.pop(context); }))]))); }

  void _showModels() { showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: const Color(0xFF11151D), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))), builder: (_) => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(18, 18, 18, 10), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [const Text('Choose Model', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)), const Spacer(), IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close))]), ..._models.map((m) => ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 4), leading: CircleAvatar(backgroundColor: const Color(0xFF1D2940), child: const Icon(Icons.auto_awesome, color: Color(0xFF6EA8FF))), title: Text(m['name']!, style: const TextStyle(fontWeight: FontWeight.w800)), subtitle: Text(m['desc']!, style: const TextStyle(color: Colors.white54)), trailing: _model == m['name'] ? const Icon(Icons.check, color: Color(0xFF22E878)) : null, onTap: () { setState(() => _model = m['name']!); Navigator.pop(context); }))]))); }

  Widget _profileMenu() => Positioned(left: 5, top: 65, child: Material(color: Colors.transparent, child: Container(width: 275, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF10151F), borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFF30384A)), boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 25)]), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const ListTile(contentPadding: EdgeInsets.zero, leading: CircleAvatar(radius: 27, backgroundColor: Color(0xFF47338D), child: Icon(Icons.person, size: 30)), title: Text('VEYLORA AI', style: TextStyle(fontWeight: FontWeight.w900)), subtitle: Text('Free Plan', style: TextStyle(color: Colors.white54))), const Divider(), _menuItem(Icons.person_outline, 'Profile', () {}), _menuItem(Icons.settings_outlined, 'App Settings', () {}), _menuItem(Icons.logout_rounded, 'Logout', () { setState(() => _menuOpen = false); })])));
  Widget _menuItem(IconData icon, String label, VoidCallback onTap) => ListTile(contentPadding: EdgeInsets.zero, leading: Icon(icon), title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)), onTap: onTap);

  @override void dispose() { _controller.dispose(); _scroll.dispose(); super.dispose(); }
}
