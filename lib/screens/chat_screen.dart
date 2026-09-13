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
  String _mode = 'Smart';

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
    setState(() { _messages.add({'role': 'user', 'content': text, 'id': _uuid.v4()}); _busy = true; });
    await _save();
    try {
      final reply = await _ai.chat(messages: _messages.map((m) => {'role': m['role']!, 'content': m['content']!}).toList());
      setState(() => _messages.add({'role': 'assistant', 'content': reply, 'id': _uuid.v4()}));
      await _save();
    } catch (e) { _error(e); } finally { if (mounted) setState(() => _busy = false); _jump(); }
  }

  Future<void> _media(bool video) async {
    final prompt = _controller.text.trim();
    if (prompt.isEmpty || _busy) return;
    _controller.clear();
    setState(() => _busy = true);
    try {
      final task = video ? await _ai.generateVideo(prompt) : await _ai.generateImage(prompt);
      setState(() => _messages.add({'role': 'assistant', 'content': '✨ VEYLORA ${video ? 'Video' : 'Image'} generation started.\n\nPrompt: $prompt\nTask ID: $task', 'id': _uuid.v4()}));
      await _save();
    } catch (e) { _error(e); } finally { if (mounted) setState(() => _busy = false); _jump(); }
  }

  void _quick(String text) { _controller.text = text; _controller.selection = TextSelection.collapsed(offset: text.length); }
  void _error(Object e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), behavior: SnackBarBehavior.floating)); }
  Future<void> _save() async => widget.prefs.setString('messages', jsonEncode(_messages));
  void _jump() => WidgetsBinding.instance.addPostFrameCallback((_) { if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut); });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Row(children: [Container(width: 34, height: 34, decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), gradient: const LinearGradient(colors: [Color(0xFF9C83FF), Color(0xFF5D7CFF)])), child: const Icon(Icons.auto_awesome, size: 20)), const SizedBox(width: 10), const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('VEYLORA AI', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)), Text('Your creative intelligence', style: TextStyle(fontSize: 10, color: Colors.white54))])]),
      actions: [PopupMenuButton<String>(tooltip: 'AI mode', initialValue: _mode, onSelected: (v) => setState(() => _mode = v), itemBuilder: (_) => ['Smart', 'Creative', 'Fast'].map((v) => PopupMenuItem(value: v, child: Text(v))).toList(), icon: const Icon(Icons.tune)), IconButton(tooltip: 'Clear conversation', onPressed: _messages.isEmpty ? null : () { setState(() => _messages = []); _save(); }, icon: const Icon(Icons.delete_outline))],
    ),
    body: Column(children: [
      Expanded(child: _messages.isEmpty ? _welcome() : ListView.builder(controller: _scroll, padding: const EdgeInsets.fromLTRB(16, 12, 16, 18), itemCount: _messages.length, itemBuilder: (c, i) => _bubble(_messages[i]))),
      if (_busy) const Padding(padding: EdgeInsets.only(bottom: 8), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: 8), Text('VEYLORA is working…', style: TextStyle(color: Colors.white60))])),
      _composer(),
    ]),
  );

  Widget _welcome() => SingleChildScrollView(child: Padding(padding: const EdgeInsets.fromLTRB(22, 45, 22, 20), child: Column(children: [
    Container(width: 82, height: 82, decoration: BoxDecoration(shape: BoxShape.circle, gradient: const LinearGradient(colors: [Color(0xFF9C83FF), Color(0xFF5D7CFF)]), boxShadow: [BoxShadow(color: const Color(0xFF8065FF).withOpacity(.3), blurRadius: 30)]), child: const Icon(Icons.auto_awesome, size: 42)),
    const SizedBox(height: 20), const Text('Meet VEYLORA', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900)),
    const SizedBox(height: 8), Text('One creative AI workspace for ideas, conversations and generation.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60, fontSize: 15, height: 1.5)),
    const SizedBox(height: 28), Wrap(spacing: 9, runSpacing: 9, alignment: WrapAlignment.center, children: [
      _PromptChip(label: 'Write a song', icon: Icons.music_note, text: 'Write an original Afro-fusion song about ambition.'),
      _PromptChip(label: 'Create an image', icon: Icons.image_outlined, text: 'Create a cinematic futuristic Nigerian city at night.'),
      _PromptChip(label: 'Create a video', icon: Icons.movie_outlined, text: 'Create a cinematic 5 second futuristic music video.'),
      _PromptChip(label: 'Build an idea', icon: Icons.lightbulb_outline, text: 'Give me a powerful startup idea I can build.'),
    ], onTap: _quick),
  ])));

  Widget _bubble(Map<String, String> m) { final user = m['role'] == 'user'; return Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: user ? MainAxisAlignment.end : MainAxisAlignment.start, children: [if (!user) Container(margin: const EdgeInsets.only(right: 8), width: 30, height: 30, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF735BE7).withOpacity(.2)), child: const Icon(Icons.auto_awesome, size: 16, color: Color(0xFFAD9BFF))), Flexible(child: GestureDetector(onLongPress: () { Clipboard.setData(ClipboardData(text: m['content'] ?? '')); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard'), behavior: SnackBarBehavior.floating)); }, child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13), decoration: BoxDecoration(color: user ? const Color(0xFF6049C8) : const Color(0xFF141925), borderRadius: BorderRadius.circular(20).copyWith(bottomRight: user ? const Radius.circular(5) : null, bottomLeft: user ? null : const Radius.circular(5))), child: Text(m['content'] ?? '', style: const TextStyle(fontSize: 15.5, height: 1.45)))))])); }

  Widget _composer() => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 12), child: Column(children: [Row(children: [Text('$_mode mode', style: const TextStyle(color: Colors.white54, fontSize: 12)), const Spacer(), const Text('Long-press a reply to copy', style: TextStyle(color: Colors.white38, fontSize: 11))]), const SizedBox(height: 6), TextField(controller: _controller, maxLines: 5, minLines: 1, textInputAction: TextInputAction.newline, decoration: InputDecoration(hintText: 'Ask anything or describe what to create…', filled: true, fillColor: const Color(0xFF121622), prefixIcon: const Icon(Icons.edit_outlined, size: 20), border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14))), const SizedBox(height: 8), Row(children: [Expanded(child: FilledButton.icon(onPressed: _busy ? null : _send, icon: const Icon(Icons.auto_awesome), label: const Text('Ask VEYLORA'))), const SizedBox(width: 5), IconButton(tooltip: 'Generate image with KIE', onPressed: _busy ? null : () => _media(false), icon: const Icon(Icons.image_outlined)), IconButton(tooltip: 'Generate video with KIE', onPressed: _busy ? null : () => _media(true), icon: const Icon(Icons.movie_outlined))])]));
}

class _PromptChip extends StatelessWidget {
  final String label, text; final IconData icon; const _PromptChip({required this.label, required this.icon, required this.text});
  @override Widget build(BuildContext context) => ActionChip(avatar: Icon(icon, size: 17), label: Text(label), onPressed: () {});
}