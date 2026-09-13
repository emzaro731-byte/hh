import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../services/ai_service.dart';

class ChatScreen extends StatefulWidget {
  final SharedPreferences prefs;
  const ChatScreen({super.key, required this.prefs});
  @override State<ChatScreen> createState()=>_ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>{
  final _controller=TextEditingController(); final _scroll=ScrollController(); final _uuid=const Uuid();
  const _ai=AiService(); const _kie=KieService(); List<Map<String,String>> _messages=[]; bool _busy=false;
  @override void initState(){super.initState(); final saved=widget.prefs.getString('messages'); if(saved!=null){try{_messages=List<Map<String,String>>.from((jsonDecode(saved) as List).map((e)=>Map<String,String>.from(e)));}catch(_){}}}
  Future<void> _send() async{final text=_controller.text.trim();if(text.isEmpty||_busy)return;_controller.clear();setState((){_messages.add({'role':'user','content':text,'id':_uuid.v4()});_busy=true;});await _save();try{final reply=await _ai.chat(messages:_messages.map((m)=>{'role':m['role']!,'content':m['content']!}).toList());setState(()=>_messages.add({'role':'assistant','content':reply,'id':_uuid.v4()}));await _save();}catch(e){_error(e);}finally{if(mounted)setState(()=>_busy=false);_jump();}}
  Future<void> _media(bool video) async{final prompt=_controller.text.trim();if(prompt.isEmpty||_busy)return;_controller.clear();setState(()=>_busy=true);try{final result=video?await _kie.generateVideo(prompt):await _kie.generateImage(prompt);setState(()=>_messages.add({'role':'assistant','content':'✨ VEYLORA ${video?'Video':'Image'}\n$result','id':_uuid.v4()}));await _save();}catch(e){_error(e);}finally{if(mounted)setState(()=>_busy=false);}}
  void _error(Object e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
  Future<void> _save()async=>widget.prefs.setString('messages',jsonEncode(_messages));
  void _jump()=>WidgetsBinding.instance.addPostFrameCallback((_){if(_scroll.hasClients)_scroll.animateTo(_scroll.position.maxScrollExtent,duration:const Duration(milliseconds:250),curve:Curves.easeOut);});
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('VEYLORA AI',style:TextStyle(fontWeight:FontWeight.w800)),actions:[IconButton(onPressed:()=>setState(()=>_messages=[]),icon:const Icon(Icons.delete_outline))]),body:Column(children:[Expanded(child:_messages.isEmpty?_welcome():ListView.builder(controller:_scroll,padding:const EdgeInsets.all(16),itemCount:_messages.length,itemBuilder:(c,i)=>_bubble(_messages[i]))),if(_busy)const Padding(padding:EdgeInsets.all(8),child:Text('VEYLORA is creating…',style:TextStyle(color:Colors.white54))),_composer()]));
  Widget _welcome()=>Center(child:Padding(padding:const EdgeInsets.all(28),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[const Icon(Icons.auto_awesome,size:60,color:Color(0xFF9C83FF)),const SizedBox(height:18),const Text('Meet VEYLORA',style:TextStyle(fontSize:32,fontWeight:FontWeight.w900)),const SizedBox(height:10),const Text('Chat with Groq. Create images and videos with KIE AI.',textAlign:TextAlign.center,style:TextStyle(color:Colors.white60,fontSize:16))])));
  Widget _bubble(Map<String,String> m){final user=m['role']=='user';return Align(alignment:user?Alignment.centerRight:Alignment.centerLeft,child:Container(margin:const EdgeInsets.only(bottom:12),padding:const EdgeInsets.symmetric(horizontal:16,vertical:12),constraints:BoxConstraints(maxWidth:MediaQuery.of(context).size.width*.86),decoration:BoxDecoration(color:user?const Color(0xFF6049C8):const Color(0xFF141925),borderRadius:BorderRadius.circular(18)),child:Text(m['content']??'',style:const TextStyle(fontSize:16,height:1.45))));}
  Widget _composer()=>SafeArea(child:Padding(padding:const EdgeInsets.fromLTRB(12,4,12,12),child:Column(children:[TextField(controller:_controller,maxLines:4,minLines:1,decoration:InputDecoration(hintText:'Message or describe what to create…',filled:true,fillColor:const Color(0xFF121622),border:OutlineInputBorder(borderRadius:BorderRadius.circular(24),borderSide:BorderSide.none),contentPadding:const EdgeInsets.symmetric(horizontal:18,vertical:14))),const SizedBox(height:8),Row(children:[Expanded(child:FilledButton.icon(onPressed:_busy?null:_send,icon:const Icon(Icons.auto_awesome),label:const Text('Chat with Groq'))),const SizedBox(width:6),IconButton(tooltip:'Generate image with KIE',onPressed:_busy?null:()=>_media(false),icon:const Icon(Icons.image)),IconButton(tooltip:'Generate video with KIE',onPressed:_busy?null:()=>_media(true),icon:const Icon(Icons.movie))])]));
}
