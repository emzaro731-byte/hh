import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_page.dart';
import 'call_page.dart';
import 'services/calls_repository.dart';
import 'offline_store.dart';

class OfflineChatPage extends StatefulWidget {
  final Conversation conversation;
  final bool dark;
  const OfflineChatPage({super.key, required this.conversation, required this.dark});
  @override State<OfflineChatPage> createState() => _OfflineChatPageState();
}

class _OfflineChatPageState extends State<OfflineChatPage> {
  final sb = Supabase.instance.client;
  final input = TextEditingController();
  List<Map<String, dynamic>> messages = [];
  RealtimeChannel? channel;
  String? uid;
  bool loading = true, calling = false;

  @override void initState() { super.initState(); uid = sb.auth.currentUser?.id; load(); }

  Future<void> load() async {
    if (uid == null) { if (mounted) setState(() => loading = false); return; }
    final cached = await OfflineStore.loadMessages(uid!, widget.conversation.id);
    if (mounted && cached.isNotEmpty) setState(() { messages = cached; loading = false; });
    try {
      final d = await sb.from('messages').select('*').eq('conversation_id', widget.conversation.id).order('created_at', ascending: true);
      final fresh = List<Map<String, dynamic>>.from(d);
      await OfflineStore.saveMessages(uid!, widget.conversation.id, fresh);
      if (mounted) setState(() { messages = fresh; loading = false; });
      channel = sb.channel('offline-cache-messages:${widget.conversation.id}')
        ..onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'messages', filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'conversation_id', value: widget.conversation.id), callback: (p) async {
          final m = Map<String, dynamic>.from(p.newRecord);
          if (m['id'] != null && !messages.any((x) => x['id'] == m['id']) && mounted) {
            setState(() => messages.add(m));
            await OfflineStore.saveMessages(uid!, widget.conversation.id, messages);
          }
        }).subscribe();
      if (uid != null) await sb.from('messages').update({'read_at': DateTime.now().toUtc().toIso8601String()}).eq('conversation_id', widget.conversation.id).neq('sender_id', uid!).isFilter('read_at', null);
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> send() async {
    final text = input.text.trim(); if (text.isEmpty || uid == null) return;
    input.clear();
    final local = {'id':'local_${DateTime.now().microsecondsSinceEpoch}','conversation_id':widget.conversation.id,'sender_id':uid,'body':text,'message_type':'text','created_at':DateTime.now().toUtc().toIso8601String()};
    setState(() => messages.add(local)); await OfflineStore.saveMessages(uid!, widget.conversation.id, messages);
    try {
      final m = await sb.from('messages').insert({'conversation_id':widget.conversation.id,'sender_id':uid,'body':text,'message_type':'text','delivered_at':DateTime.now().toUtc().toIso8601String()}).select().single();
      if (mounted) setState(() { messages.removeWhere((x) => x['id'] == local['id']); if (!messages.any((x) => x['id'] == m['id'])) messages.add(Map<String,dynamic>.from(m)); });
      await OfflineStore.saveMessages(uid!, widget.conversation.id, messages);
    } catch (_) {}
  }

  Future<String?> peer() async {
    if (uid == null) return null;
    final r = await sb.from('conversation_members').select('user_id').eq('conversation_id', widget.conversation.id).neq('user_id', uid!).limit(1);
    return r.isEmpty ? null : r.first['user_id']?.toString();
  }
  Future<void> call(bool video) async {
    if (calling || uid == null) return;
    try { setState(() => calling=true); final p=await peer(); if(p==null) throw Exception('Other participant not found'); final r=await sb.from('calls').insert({'caller_id':uid,'callee_id':p,'type':video?'video':'audio','status':'ringing'}).select().single(); await Navigator.push(context,MaterialPageRoute(builder:(_)=>CallPage(callId:r['id'].toString(),video:video,caller:true))); } catch(e) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Call failed: $e'))); } finally { if(mounted)setState(()=>calling=false); }
  }
  String time(dynamic v) { if(v==null)return ''; try{return TimeOfDay.fromDateTime(DateTime.parse(v.toString()).toLocal()).format(context);}catch(_){return '';} }

  @override void dispose(){ if(channel!=null) sb.removeChannel(channel!); input.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Theme(data:widget.dark?ThemeData.dark(useMaterial3:true):ThemeData(useMaterial3:true,colorSchemeSeed:const Color(0xff2563eb)),child:Scaffold(
    appBar:AppBar(title:Row(children:[CircleAvatar(child:Text(widget.conversation.name.isEmpty?'G':widget.conversation.name[0].toUpperCase())),const SizedBox(width:10),Expanded(child:Text(widget.conversation.name,overflow:TextOverflow.ellipsis))]),actions:[IconButton(onPressed:calling?null:()=>call(false),icon:const Icon(Icons.call)),IconButton(onPressed:calling?null:()=>call(true),icon:const Icon(Icons.videocam))]),
    body:Column(children:[Expanded(child:loading?const Center(child:CircularProgressIndicator()):messages.isEmpty?const Center(child:Text('No messages cached yet')):ListView.builder(padding:const EdgeInsets.all(12),itemCount:messages.length,itemBuilder:(_,i){final m=messages[i];final mine=m['sender_id']==uid;return Align(alignment:mine?Alignment.centerRight:Alignment.centerLeft,child:Container(constraints:const BoxConstraints(maxWidth:330),margin:const EdgeInsets.only(bottom:8),padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:mine?const Color(0xff2563eb):(widget.dark?const Color(0xff202938):const Color(0xffe7ebf2)),borderRadius:BorderRadius.circular(16)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[if(m['message_type']=='text')Text((m['body']??'').toString(),style:TextStyle(color:mine?Colors.white:null,fontSize:15)),if(m['message_type']!='text')Row(children:[const Icon(Icons.insert_drive_file),const SizedBox(width:8),Expanded(child:Text((m['file_name']??m['body']??'Attachment').toString()))]),const SizedBox(height:4),Text(time(m['created_at']),style:TextStyle(color:mine?Colors.white70:Colors.grey,fontSize:10))])));}),),SafeArea(child:Padding(padding:const EdgeInsets.all(8),child:Row(children:[Expanded(child:TextField(controller:input,textInputAction:TextInputAction.send,onSubmitted:(_)=>send(),decoration:InputDecoration(hintText:'Message',filled:true,border:OutlineInputBorder(borderRadius:BorderRadius.circular(24))))),IconButton(onPressed:send,icon:const Icon(Icons.send,color:Color(0xff2563eb)))])))])
  ));
}
