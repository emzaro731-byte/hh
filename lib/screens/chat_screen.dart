import 'dart:convert';
import 'package:flutter/material.dart';
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
  late final AiService _ai;
  List<Map<String, String>> _messages = [];
  bool _busy = false;
  String _endpoint = '';

  @override
  void initState() {
    super.initState();
    _endpoint = widget.prefs.getString('endpoint') ?? '';
    final saved = widget.prefs.getString('messages');
    if (saved != null) {
      try { _messages = List<Map<String,String>>.from((jsonDecode(saved) as List).map((e) => Map<String,String>.from(e))); } catch (_) {}
    }
    _ai = AiService(endpoint: _endpoint.isEmpty ? 'https://YOUR-SUPABASE-PROJECT.supabase.co/functions/v1/chat' : _endpoint);
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;
    _controller.clear();
    setState(() { _messages.add({'role':'user','content':text,'id':_uuid.v4()}); _busy = true; });
    await _save();
    try {
      final reply = await _ai.chat(messages: _messages.map((m) => {'role':m['role']!, 'content':m['content']!}).toList());
      setState(() => _messages.add({'role':'assistant','content':reply,'id':_uuid.v4()}));
      await _save();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not reach VEYLORA AI: $e')));
    } finally { if (mounted) setState(() => _busy = false); _jump(); }
  }

  Future<void> _save() async => widget.prefs.setString('messages', jsonEncode(_messages));
  void _jump() { WidgetsBinding.instance.addPostFrameCallback((_) { if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds:250), curve: Curves.easeOut); }); }

  void _settings() {
    final c = TextEditingController(text: _endpoint);
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => Padding(
      padding: EdgeInsets.fromLTRB(20,20,20,20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('VEYLORA AI Settings', style: TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
        const SizedBox(height:8), const Text('Enter your secure backend/Edge Function URL. Never ship a private AI API key in the Flutter app.'),
        const SizedBox(height:14), TextField(controller:c, decoration: const InputDecoration(labelText:'AI endpoint', border:OutlineInputBorder())),
        const SizedBox(height:14), FilledButton(onPressed: () { setState(() => _endpoint=c.text.trim()); widget.prefs.setString('endpoint', c.text.trim()); Navigator.pop(context); }, child: const Text('Save')),
      ]),
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Row(children:[Container(width:38,height:38,decoration:BoxDecoration(borderRadius:BorderRadius.circular(12),gradient:const LinearGradient(colors:[Color(0xFF7C5CFF),Color(0xFF25D6C7)])),child:const Icon(Icons.auto_awesome)),const SizedBox(width:10),const Text('VEYLORA AI',style:TextStyle(fontWeight:FontWeight.w800))]), actions:[IconButton(onPressed:_settings,icon:const Icon(Icons.tune)),IconButton(onPressed:(){setState(()=>_messages=[]);_save();},icon:const Icon(Icons.delete_outline))]),
    body: Column(children:[
      Expanded(child: _messages.isEmpty ? _welcome() : ListView.builder(controller:_scroll,padding:const EdgeInsets.all(16),itemCount:_messages.length,itemBuilder:(c,i)=>_bubble(_messages[i]))),
      if (_busy) const Padding(padding:EdgeInsets.only(bottom:8),child:Text('VEYLORA is thinking…',style:TextStyle(color:Colors.white54))),
      _composer(),
    ]),
  );

  Widget _welcome() => Center(child:Padding(padding:const EdgeInsets.all(28),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[const Icon(Icons.auto_awesome,size:58,color:Color(0xFF9C83FF)),const SizedBox(height:18),const Text('Meet VEYLORA',style:TextStyle(fontSize:32,fontWeight:FontWeight.w900)),const SizedBox(height:10),const Text('Your intelligent creative partner for ideas, coding, writing, learning and problem solving.',textAlign:TextAlign.center,style:TextStyle(color:Colors.white60,fontSize:16)),const SizedBox(height:24),Wrap(spacing:8,runSpacing:8,alignment:WrapAlignment.center,children:['Write a song','Build an app','Explain this','Brainstorm ideas'].map((x)=>ActionChip(label:Text(x),onPressed:(){_controller.text=x;_send();})).toList())])));

  Widget _bubble(Map<String,String> m) { final user=m['role']=='user'; return Align(alignment:user?Alignment.centerRight:Alignment.centerLeft,child:Container(margin:const EdgeInsets.only(bottom:12),padding:const EdgeInsets.symmetric(horizontal:16,vertical:12),constraints:BoxConstraints(maxWidth:MediaQuery.of(context).size.width*.86),decoration:BoxDecoration(color:user?const Color(0xFF6049C8):const Color(0xFF141925),borderRadius:BorderRadius.circular(18)),child:Text(m['content']??'',style:const TextStyle(fontSize:16,height:1.45)))); }
  Widget _composer() => SafeArea(child:Padding(padding:const EdgeInsets.fromLTRB(12,4,12,12),child:Row(crossAxisAlignment:CrossAxisAlignment.end,children:[Expanded(child:TextField(controller:_controller,maxLines:5,minLines:1,textInputAction:TextInputAction.new,onSubmitted:(_)=>_send(),decoration:InputDecoration(hintText:'Message VEYLORA…',filled:true,fillColor:const Color(0xFF121622),border:OutlineInputBorder(borderRadius:BorderRadius.circular(24),borderSide:BorderSide.none),contentPadding:const EdgeInsets.symmetric(horizontal:18,vertical:14)))),const SizedBox(width:8),FloatingActionButton.small(onPressed:_busy?null:_send,child:const Icon(Icons.arrow_upward))])));
}
