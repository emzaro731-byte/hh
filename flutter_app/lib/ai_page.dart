import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class AIPage extends StatefulWidget { const AIPage({super.key}); @override State<AIPage> createState()=>_AIPageState(); }
class _AIPageState extends State<AIPage> {
  final sb=Supabase.instance.client, prompt=TextEditingController();
  String mode='chat',model='',status=''; bool loading=false;
  Map<String,dynamic>? result; List<dynamic> history=[];
  @override void initState(){super.initState();loadHistory();}
  @override void dispose(){prompt.dispose();super.dispose();}
  Future<void> loadHistory() async { try { final d=await sb.from('ai_generations').select('id,type,prompt,model,result_urls,result_text,created_at').order('created_at',ascending:false).limit(30); if(mounted)setState(()=>history=d); } catch(_){ } }
  void choose(String x){setState(() {mode=x;result=null;status='';model=x=='image'?'flux-2/flex-text-to-image':x=='video'?'runway':x=='music'?'suno':'';});}
  Future<void> run() async {
    final text=prompt.text.trim(); if(text.isEmpty||loading)return;
    setState(() {loading=true;status='Starting…';result=null;});
    try {
      final r=await sb.functions.invoke('ai-generate',body:{'type':mode,'prompt':text,'options':{'model':model,'aspectRatio':mode=='video'?'9:16':'1:1','duration':5,'quality':'720p'}});
      var done=Map<String,dynamic>.from(r.data??{});
      if(mode!='chat'){
        final task=done['taskId']; if(task==null)throw Exception('No generation task was returned');
        final started=DateTime.now();
        while(DateTime.now().difference(started)<const Duration(minutes:15)){
          await Future.delayed(const Duration(seconds:3));
          final s=await sb.functions.invoke('ai-generate',body:{'action':'status','type':mode,'taskId':task}); done=Map<String,dynamic>.from(s.data??{});
          if(mounted)setState(()=>status=done['status']?.toString()??'Generating…');
          final state=(done['status']??'').toString().toLowerCase();
          if(done['url']!=null||(done['urls'] is List&&done['urls'].isNotEmpty)||['success','succeeded','complete','completed'].contains(state))break;
        }
      }
      await sb.functions.invoke('ai-save',body:{'type':mode,'prompt':text,'model':model,'taskId':done['taskId'],'urls':done['urls']??(done['url']!=null?[done['url']]:[]),'resultText':done['message']});
      if(mounted)setState(() {result=done;status='Complete';}); await loadHistory();
    } catch(e){if(mounted)setState(() {result={'message':e.toString()};status='Failed';});} finally {if(mounted)setState(()=>loading=false);}
  }
  IconData icon(String x)=>x=='chat'?Icons.auto_awesome:x=='image'?Icons.image_outlined:x=='video'?Icons.movie_creation_outlined:Icons.music_note;
  String title(String x)=>x.isEmpty?'AI':x[0].toUpperCase()+x.substring(1);
  List<String> urls(Map<String,dynamic>? r){if(r==null)return[];final u=r['urls'];if(u is List)return u.whereType<String>().toList();if(r['url']!=null)return[r['url'].toString()];return[];}
  Future<void> open(String u)async{await launchUrl(Uri.parse(u),mode:LaunchMode.externalApplication);}
  @override Widget build(BuildContext context){final cs=Theme.of(context).colorScheme,media=urls(result);return Scaffold(
    appBar:AppBar(title:const Text('GG AI Studio',style:TextStyle(fontWeight:FontWeight.w900)),actions:[IconButton(onPressed:loadHistory,icon:const Icon(Icons.history))]),
    body:CustomScrollView(slivers:[SliverToBoxAdapter(child:Padding(padding:const EdgeInsets.fromLTRB(16,14,16,8),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('Create with AI',style:Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.w900)),const SizedBox(height:5),Text('Chat, images, video and music in one studio.',style:TextStyle(color:cs.onSurfaceVariant)),const SizedBox(height:16),
      SizedBox(height:92,child:ListView.separated(scrollDirection:Axis.horizontal,itemCount:4,separatorBuilder:(_,__)=>const SizedBox(width:10),itemBuilder:(_,i){final x=['chat','image','video','music'][i],selected=mode==x;return GestureDetector(onTap:()=>choose(x),child:AnimatedContainer(duration:const Duration(milliseconds:180),width:104,padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:selected?cs.primaryContainer:cs.surfaceContainerHighest,borderRadius:BorderRadius.circular(20),border:Border.all(color:selected?cs.primary:cs.outlineVariant)),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Icon(icon(x),color:selected?cs.primary:null),const SizedBox(height:6),Text(title(x),style:const TextStyle(fontWeight:FontWeight.w700))])));})),
      const SizedBox(height:18),Card(elevation:0,child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(mode=='chat'?'Ask GG AI anything':'Describe your ${title(mode)}',style:const TextStyle(fontWeight:FontWeight.w800)),const SizedBox(height:10),TextField(controller:prompt,minLines:4,maxLines:8,enabled:!loading,decoration:InputDecoration(hintText:mode=='chat'?'Write your question…':'Describe exactly what you want…',prefixIcon:Icon(icon(mode)),filled:true,border:OutlineInputBorder(borderRadius:BorderRadius.circular(18)))),if(mode!='chat')Padding(padding:const EdgeInsets.only(top:10),child:Row(children:[Icon(Icons.tune,size:16,color:cs.onSurfaceVariant),const SizedBox(width:6),Expanded(child:Text(model,style:TextStyle(color:cs.onSurfaceVariant,fontSize:12)))])),const SizedBox(height:12),SizedBox(width:double.infinity,height:52,child:FilledButton.icon(onPressed:loading?null:run,icon:Icon(loading?Icons.hourglass_top:Icons.auto_awesome),label:Text(loading?'Creating…':mode=='chat'?'Ask GG AI':'Generate ${title(mode)}')))]))),
    ]))),if(loading)const SliverToBoxAdapter(child:Padding(padding:EdgeInsets.all(20),child:Center(child:CircularProgressIndicator()))),if(status.isNotEmpty&&!loading)SliverToBoxAdapter(child:Padding(padding:const EdgeInsets.symmetric(horizontal:16,vertical:8),child:Text(status,style:const TextStyle(fontWeight:FontWeight.w700)))),
    if(result!=null)SliverToBoxAdapter(child:Padding(padding:const EdgeInsets.all(16),child:Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[Icon(icon(mode)),const SizedBox(width:8),Text('${title(mode)} result',style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900))]),const SizedBox(height:12),if(result!['message']!=null)Text(result!['message'].toString(),style:const TextStyle(fontSize:15,height:1.45)),if(media.isNotEmpty&&mode=='image')ClipRRect(borderRadius:BorderRadius.circular(16),child:Image.network(media.first,width:double.infinity,height:280,fit:BoxFit.cover,errorBuilder:(_,__,___)=>const SizedBox(height:120,child:Center(child:Text('Image preview unavailable'))))),if(media.isNotEmpty)Padding(padding:const EdgeInsets.only(top:12),child:Wrap(spacing:8,runSpacing:8,children:[for(final u in media)FilledButton.tonalIcon(onPressed:()=>open(u),icon:Icon(mode=='video'?Icons.play_circle:mode=='music'?Icons.headphones:Icons.open_in_new),label:Text(mode=='video'?'Watch':mode=='music'?'Listen':'Open'))]))])))),
    if(history.isNotEmpty)SliverToBoxAdapter(child:Padding(padding:const EdgeInsets.fromLTRB(16,12,16,30),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('Recent creations',style:TextStyle(fontSize:20,fontWeight:FontWeight.w900)),const SizedBox(height:8),for(final h in history)Card(margin:const EdgeInsets.only(bottom:8),child:ListTile(leading:CircleAvatar(child:Icon(icon('${h['type']??'chat'}'),size:20)),title:Text('${h['prompt']??''}',maxLines:2,overflow:TextOverflow.ellipsis),subtitle:Text('${title('${h['type']??'chat'}')} • ${h['model']??'GG AI'}'),trailing:const Icon(Icons.chevron_right)))]))),
  ]));}
}
