import React,{useEffect,useMemo,useState}from'react';
import{ActivityIndicator,Image,Linking,Modal,Pressable,ScrollView,StyleSheet,Text,TextInput,View}from'react-native';
import{generateAI,loadAIHistory,saveAIGeneration,waitForAI,AIGeneration}from'../lib/ai';
import{supabase}from'../lib/supabase';

type Props={visible:boolean;onClose:()=>void;dark?:boolean};
type HistoryItem={id:string;type:string;prompt:string;model:string|null;result_urls:string[];result_text:string|null;created_at:string};
type ModelItem={id:string;name:string;speed?:string;provider?:string};
type ModelCatalog={chat:ModelItem[];image:ModelItem[];video:ModelItem[];music:ModelItem[]};

const FALLBACK:ModelCatalog={
 chat:[
  {id:'openai/gpt-oss-120b',name:'GPT-OSS 120B',speed:'Expert',provider:'Groq'},
  {id:'openai/gpt-oss-20b',name:'GPT-OSS 20B',speed:'Ultra Fast',provider:'Groq'},
  {id:'qwen/qwen3.8-27b',name:'Qwen 3.8 27B',speed:'Expert',provider:'Groq'},
  {id:'qwen/qwen3.6-27b',name:'Qwen 3.6 27B',speed:'Fast',provider:'Groq'},
  {id:'minimaxai/minimax-m2.7',name:'MiniMax M2.7',speed:'Fast',provider:'Groq'},
  {id:'groq/compound',name:'Groq Compound',speed:'Auto',provider:'Groq'},
  {id:'groq/compound-mini',name:'Groq Compound Mini',speed:'Fast',provider:'Groq'}
 ],
 image:[
  {id:'seedream/5.0-lite',name:'Seedream 5.0 Lite',speed:'Fast',provider:'KIE'},
  {id:'seedream/5.0-pro',name:'Seedream 5.0 Pro',speed:'Expert',provider:'KIE'},
  {id:'google/imagen4-fast',name:'Google Imagen 4 Fast',speed:'Fast',provider:'KIE'},
  {id:'google/imagen4-ultra',name:'Google Imagen 4 Ultra',speed:'Expert',provider:'KIE'},
  {id:'google/nano-banana-2',name:'Nano Banana 2',speed:'Fast',provider:'KIE'},
  {id:'google/nano-banana-pro',name:'Nano Banana Pro',speed:'Expert',provider:'KIE'},
  {id:'flux-2/flex-text-to-image',name:'Flux 2 Flex',speed:'Fast',provider:'KIE'},
  {id:'flux-2/pro-text-to-image',name:'Flux 2 Pro',speed:'Quality',provider:'KIE'},
  {id:'grok-imagine/text-to-image',name:'Grok Imagine',speed:'Fast',provider:'KIE'},
  {id:'gpt-image-2',name:'GPT Image 2',speed:'Quality',provider:'KIE'},
  {id:'z-image',name:'Z-image',speed:'Fast',provider:'KIE'}
 ],
 video:[
  {id:'kling-3.0',name:'Kling 3.0',speed:'Expert',provider:'KIE'},
  {id:'kling/v3-turbo-text-to-video',name:'Kling V3 Turbo',speed:'Ultra Fast',provider:'KIE'},
  {id:'kling-2.6/text-to-video',name:'Kling 2.6',speed:'Fast',provider:'KIE'},
  {id:'veo3/veo-3.1-fast',name:'Veo 3.1 Fast',speed:'Fast',provider:'KIE'},
  {id:'veo3/veo-3.1-quality',name:'Veo 3.1 Quality',speed:'Expert',provider:'KIE'},
  {id:'pixverse/v6-text-to-video',name:'PixVerse V6',speed:'Fast',provider:'KIE'},
  {id:'wan/2.7-text-to-video',name:'Wan 2.7',speed:'Fast',provider:'KIE'},
  {id:'runway',name:'Runway',speed:'Quality',provider:'KIE'},
  {id:'grok-imagine/text-to-video',name:'Grok Imagine Video',speed:'Fast',provider:'KIE'},
  {id:'seedance/2.0',name:'Seedance 2.0',speed:'Fast',provider:'KIE'},
  {id:'gemini-omni-video',name:'Gemini Omni Video',speed:'Expert',provider:'KIE'}
 ],
 music:[
  {id:'V6',name:'Suno V6',speed:'Expert',provider:'KIE'},
  {id:'V6_MINI',name:'Suno V6 Mini',speed:'Fast',provider:'KIE'},
  {id:'V6_WILD',name:'Suno V6 Wild',speed:'Creative',provider:'KIE'},
  {id:'V5_5',name:'Suno V5.5',speed:'Quality',provider:'KIE'},
  {id:'V5',name:'Suno V5',speed:'Fast',provider:'KIE'},
  {id:'V4_5ALL',name:'Suno V4.5 All',speed:'Fast',provider:'KIE'},
  {id:'V4_5PLUS',name:'Suno V4.5 Plus',speed:'Quality',provider:'KIE'},
  {id:'V4_5',name:'Suno V4.5',speed:'Fast',provider:'KIE'},
  {id:'V4',name:'Suno V4',speed:'Classic',provider:'KIE'}
 ]
};

const META:{key:keyof ModelCatalog;title:string;icon:string;subtitle:string}[]=[
 {key:'chat',title:'Ask',icon:'✦',subtitle:'Premium intelligence'},
 {key:'image',title:'Imagine',icon:'◈',subtitle:'Image generation'},
 {key:'video',title:'Video',icon:'▶',subtitle:'Cinematic generation'},
 {key:'music',title:'Music',icon:'♫',subtitle:'Music generation'}
];

export default function AIStudio({visible,onClose,dark=false}:Props){
 const[mode,setMode]=useState<keyof ModelCatalog>('chat');
 const[prompt,setPrompt]=useState('');const[loading,setLoading]=useState(false);const[result,setResult]=useState<AIGeneration|null>(null);const[status,setStatus]=useState('');
 const[history,setHistory]=useState<HistoryItem[]>([]);const[showHistory,setShowHistory]=useState(false);const[showModels,setShowModels]=useState(false);const[query,setQuery]=useState('');const[customModel,setCustomModel]=useState('');
 const[models,setModels]=useState<ModelCatalog>(FALLBACK);const[model,setModel]=useState(FALLBACK.chat[0].id);
 const bg=dark?'#090A0D':'#f6f8fc',card=dark?'#191A1E':'#fff',fg=dark?'#F7F7F8':'#111827',muted=dark?'#9A9CA3':'#667085';
 useEffect(()=>{if(visible){refreshHistory();loadModels()}},[visible]);
 async function refreshHistory(){try{setHistory((await loadAIHistory()) as HistoryItem[])}catch(_e){}}
 async function loadModels(){try{const{data,error}=await supabase.functions.invoke('ai-generate',{body:{action:'models'}});if(!error&&data?.models)setModels((old)=>({...old,...data.models,chat:data.chat?.length?data.chat:old.chat}))}catch(_e){}}
 const currentModels=models[mode]||[];
 const filtered=useMemo(()=>currentModels.filter(x=>(x.name+' '+x.id+' '+(x.provider||'')).toLowerCase().includes(query.toLowerCase())),[currentModels,query]);
 const selected=models[mode]?.find(x=>x.id===model);
 const selectedName=selected?.name||model;
 function chooseMode(next:keyof ModelCatalog){setMode(next);setResult(null);setStatus('');setQuery('');setCustomModel('');setShowModels(false);setModel(models[next]?.[0]?.id||'')}
 function chooseModel(id:string){setModel(id);setCustomModel('');setShowModels(false);setQuery('')}
 function useCustom(){const id=customModel.trim();if(!id)return;setModel(id);setShowModels(false);setQuery('');}
 async function run(){if(!prompt.trim()||loading)return;setLoading(true);setResult(null);setStatus('Connecting…');try{const started=await generateAI(mode,prompt.trim(),{model,aspectRatio:mode==='video'?'9:16':'1:1',duration:5,quality:'720p'});let done=started;if(mode!=='chat'){if(!started.taskId)throw new Error('No generation task was returned');setStatus('Generating…');done=await waitForAI(mode,started.taskId,x=>setStatus(x.status?`Generating… ${x.status}`:'Generating…'));}setResult(done);setStatus('Complete');try{await saveAIGeneration(mode,prompt.trim(),done,model);await refreshHistory()}catch(_e){}}catch(e){setResult({message:e instanceof Error?e.message:'Generation failed'});setStatus('Failed')}finally{setLoading(false)}}
 const openResult=(url:string)=>Linking.openURL(url).catch(()=>{});
 async function savedUrl(path:string){const{data}=await supabase.storage.from('ai-generations').createSignedUrl(path,3600);return data?.signedUrl||''}
 async function openHistoryItem(item:HistoryItem){if(item.result_urls?.length){const u=await savedUrl(item.result_urls[0]);if(u)openResult(u)}}
 const icon=mode==='chat'?'✦':mode==='image'?'◈':mode==='video'?'▶':'♫';
 return <Modal visible={visible} animationType="slide" onRequestClose={onClose}>
  <View style={[s.root,{backgroundColor:bg}]}>
   <View style={s.topbar}><Pressable onPress={onClose} style={s.topIcon}><Text style={[s.close,{color:fg}]}>×</Text></Pressable><View style={s.brand}><Text style={[s.brandTitle,{color:fg}]}>GG AI</Text><Text style={{color:muted,fontSize:11,fontWeight:'700'}}>Premium Studio</Text></View><Pressable onPress={()=>setShowHistory(!showHistory)} style={s.topIcon}><Text style={{color:fg,fontSize:20}}>◷</Text></Pressable></View>
   {!showHistory&&<View style={s.mainTabs}>{META.map(x=><Pressable key={x.key} onPress={()=>chooseMode(x.key)} style={s.mainTab}><Text style={[s.mainTabText,{color:mode===x.key?fg:muted}]}>{x.title}</Text>{mode===x.key&&<View style={s.underline}/>}</Pressable>)}</View>}
   <ScrollView contentContainerStyle={s.content} keyboardShouldPersistTaps="handled">
    {showHistory?<>
      <View style={s.historyHead}><View><Text style={[s.heroTitle,{color:fg}]}>Your creations</Text><Text style={{color:muted,marginTop:4}}>Everything you generated in GG AI</Text></View><Pressable onPress={refreshHistory}><Text style={s.blue}>Refresh</Text></Pressable></View>
      {history.length===0?<Text style={{color:muted,paddingVertical:30}}>No saved generations yet.</Text>:history.map(item=><Pressable key={item.id} onPress={()=>openHistoryItem(item)} style={[s.historyCard,{backgroundColor:card}]}><Text style={s.historyIcon}>{item.type==='chat'?'✦':item.type==='image'?'◈':item.type==='video'?'▶':'♫'}</Text><View style={{flex:1}}><Text numberOfLines={2} style={{color:fg,fontWeight:'800'}}>{item.prompt}</Text><Text style={{color:muted,marginTop:5,fontSize:11}}>{item.model||'GG AI'} • {new Date(item.created_at).toLocaleString()}</Text></View></Pressable>)}
    </>:<>
      <View style={s.hero}><View style={{flex:1}}><Text style={s.kicker}>{META.find(x=>x.key===mode)?.subtitle.toUpperCase()}</Text><Text style={[s.heroTitle,{color:fg}]}>{mode==='chat'?'What do you want to create?':mode==='image'?'Imagine anything.':mode==='video'?'Bring your idea to life.':'Make your next sound.'}</Text><Text style={{color:muted,marginTop:5}}>Switch models anytime without leaving the studio.</Text></View><Text style={s.heroIcon}>{icon}</Text></View>
      <Text style={[s.sectionLabel,{color:fg}]}>Model</Text>
      <Pressable onPress={()=>setShowModels(true)} style={[s.modelButton,{backgroundColor:card}]}><View style={s.modelLogo}><Text style={{color:'#fff',fontSize:17,fontWeight:'900'}}>{selected?.provider==='Groq'?'G':'K'}</Text></View><View style={{flex:1}}><Text style={{color:fg,fontSize:16,fontWeight:'900'}}>{selectedName}</Text><Text style={{color:muted,fontSize:11,marginTop:3}}>{selected?.provider||'Custom'} • {selected?.speed||'Model'} • Tap to switch</Text></View><Text style={{color:fg,fontSize:20}}>⌄</Text></Pressable>
      <View style={s.tierRow}><View style={s.tier}><Text style={s.tierIcon}>⚡</Text><View><Text style={{color:fg,fontWeight:'900'}}>Fast</Text><Text style={{color:muted,fontSize:10}}>Quick responses</Text></View></View><View style={s.tier}><Text style={s.tierIcon}>✦</Text><View><Text style={{color:fg,fontWeight:'900'}}>Expert</Text><Text style={{color:muted,fontSize:10}}>Highest quality</Text></View></View><View style={s.tier}><Text style={s.tierIcon}>∞</Text><View><Text style={{color:fg,fontWeight:'900'}}>Auto</Text><Text style={{color:muted,fontSize:10}}>Best model</Text></View></View></View>
      <TextInput multiline value={prompt} onChangeText={setPrompt} placeholder={mode==='chat'?'Ask anything…':mode==='image'?'Describe the image you want…':mode==='video'?'Describe the video you want…':'Describe the music you want…'} placeholderTextColor={muted} style={[s.prompt,{backgroundColor:card,color:fg}]}/>
      <View style={s.composerRow}><Pressable style={[s.add,{backgroundColor:card}]}><Text style={{color:fg,fontSize:28}}>+</Text></Pressable><Pressable disabled={loading||!prompt.trim()} onPress={run} style={[s.generate,{opacity:(loading||!prompt.trim())?.5:1}]}><Text style={s.generateText}>{loading?'Creating…':mode==='chat'?'Ask GG':`Generate ${META.find(x=>x.key===mode)?.title}`}</Text><Text style={s.generateModel}>{selectedName}</Text></Pressable></View>
      {loading&&<View style={s.progress}><ActivityIndicator size="small"/><Text style={{color:muted,marginLeft:10}}>{status||'Working…'}</Text></View>}
      {result?.message&&mode==='chat'&&<View style={[s.chatResult,{backgroundColor:card}]}><Text style={{color:fg,fontSize:16,lineHeight:24}}>{result.message}</Text></View>}
      {result?.message&&mode!=='chat'&&<View style={s.error}><Text style={{color:'#ef4444'}}>{result.message}</Text></View>}
      {result?.url&&<View style={[s.result,{backgroundColor:card}]}>{mode==='image'?<Image source={{uri:result.url}} style={s.resultImage}/>:<Pressable onPress={()=>openResult(result.url!)} style={s.open}><Text style={s.openText}>{mode==='video'?'▶ Open video':'♫ Open audio'}</Text></Pressable>}</View>}
      {result?.urls?.map((u,i)=><View key={i} style={[s.result,{backgroundColor:card}]}>{mode==='image'?<Image source={{uri:u}} style={s.resultImage}/>:<Pressable onPress={()=>openResult(u)} style={s.open}><Text style={s.openText}>{mode==='video'?'▶ Open video':'♫ Open audio'} {result.urls!.length>1?i+1:''}</Text></Pressable>}</View>)}
      {result?.taskId&&<View style={[s.task,{backgroundColor:card}]}><Text style={{color:fg,fontWeight:'900'}}>{status==='Complete'?'Generation complete':'Generation task'}</Text><Text style={{color:muted,marginTop:4}}>{result.taskId}</Text></View>}
    </>}
   </ScrollView>

   <Modal visible={showModels} transparent animationType="slide" onRequestClose={()=>setShowModels(false)}>
    <View style={s.sheetBackdrop}><View style={[s.sheet,{backgroundColor:dark?'#17181C':'#fff'}]}>
      <View style={s.sheetHandle}/><View style={s.sheetHeader}><View><Text style={[s.sheetTitle,{color:fg}]}>Choose model</Text><Text style={{color:muted,fontSize:11,marginTop:3}}>Switch instantly • {currentModels.length} models shown</Text></View><Pressable onPress={()=>setShowModels(false)}><Text style={{color:fg,fontSize:28}}>×</Text></Pressable></View>
      <TextInput value={query} onChangeText={setQuery} placeholder="Search models…" placeholderTextColor={muted} style={[s.search,{backgroundColor:card,color:fg}]}/>
      <View style={s.modePills}>{META.map(x=><Pressable key={x.key} onPress={()=>{setMode(x.key);setQuery('');setCustomModel('');setModel(models[x.key]?.[0]?.id||'')}} style={[s.pill,{backgroundColor:mode===x.key?'#F4F4F5':card}]}><Text style={{color:mode===x.key?'#111':'#888',fontWeight:'900'}}>{x.title}</Text></Pressable>)}</View>
      <ScrollView style={{maxHeight:350}} keyboardShouldPersistTaps="handled">{filtered.map(x=><Pressable key={x.id} onPress={()=>chooseModel(x.id)} style={[s.modelRow,{backgroundColor:x.id===model?'#292A2E':card}]}><View style={s.modelLogoSmall}><Text style={{color:'#fff',fontWeight:'900'}}>{x.provider==='Groq'?'G':'K'}</Text></View><View style={{flex:1}}><Text style={{color:x.id===model?'#fff':fg,fontWeight:'900'}}>{x.name}</Text><Text style={{color:x.id===model?'#B9BBC1':muted,fontSize:10,marginTop:3}}>{x.provider||'KIE'} • {x.speed||'Model'} • {x.id}</Text></View>{x.id===model&&<Text style={{color:'#fff',fontSize:18}}>✓</Text>}</Pressable>)}
      <View style={[s.custom,{backgroundColor:card}]}><Text style={{color:fg,fontWeight:'900'}}>Use any supported model ID</Text><TextInput value={customModel} onChangeText={setCustomModel} autoCapitalize="none" placeholder={mode==='chat'?'e.g. openai/gpt-oss-120b':'e.g. provider/model-id'} placeholderTextColor={muted} style={[s.customInput,{color:fg}]}/><Pressable disabled={!customModel.trim()} onPress={useCustom} style={[s.customButton,{opacity:customModel.trim()?1:.45}]}><Text style={{color:'#111',fontWeight:'900'}}>Use this model</Text></Pressable></View>
    </View></View>
   </Modal>
  </View>
 </Modal>
}

const s=StyleSheet.create({
 root:{flex:1},topbar:{height:70,paddingHorizontal:14,flexDirection:'row',alignItems:'center',justifyContent:'space-between'},topIcon:{width:42,height:42,borderRadius:21,alignItems:'center',justifyContent:'center'},close:{fontSize:34},brand:{alignItems:'center'},brandTitle:{fontSize:19,fontWeight:'900'},mainTabs:{height:58,flexDirection:'row',alignItems:'flex-end',justifyContent:'space-around',borderBottomWidth:1,borderBottomColor:'#24252A'},mainTab:{height:58,minWidth:72,alignItems:'center',justifyContent:'flex-end'},mainTabText:{fontSize:17,fontWeight:'900',paddingBottom:13},underline:{height:4,width:31,borderRadius:3,backgroundColor:'#8E8F94',marginBottom:-1},content:{padding:18,paddingBottom:42},hero:{minHeight:150,borderRadius:25,padding:20,backgroundColor:'#1B1C20',flexDirection:'row',alignItems:'center',marginBottom:20},kicker:{color:'#A9AAAF',fontSize:10,fontWeight:'900',letterSpacing:1.4},heroTitle:{fontSize:25,fontWeight:'900',marginTop:7},heroIcon:{fontSize:42,color:'#fff',marginLeft:12},sectionLabel:{fontSize:14,fontWeight:'900',marginBottom:8},modelButton:{borderRadius:18,padding:13,flexDirection:'row',alignItems:'center',marginBottom:12},modelLogo:{width:42,height:42,borderRadius:14,backgroundColor:'#282A2F',alignItems:'center',justifyContent:'center',marginRight:12},tierRow:{flexDirection:'row',gap:8,marginBottom:16},tier:{flex:1,minHeight:58,borderRadius:16,backgroundColor:'#141519',padding:10,flexDirection:'row',alignItems:'center',gap:8},tierIcon:{color:'#fff',fontSize:18},prompt:{minHeight:170,borderRadius:22,padding:16,textAlignVertical:'top',fontSize:16,marginBottom:10},composerRow:{flexDirection:'row',gap:9},add:{width:54,height:54,borderRadius:18,alignItems:'center',justifyContent:'center'},generate:{flex:1,minHeight:54,borderRadius:18,backgroundColor:'#F4F4F5',paddingHorizontal:16,justifyContent:'center'},generateText:{color:'#111',fontWeight:'900',fontSize:16},generateModel:{color:'#777',fontSize:9,fontWeight:'700',marginTop:2},progress:{marginTop:14,padding:14,borderRadius:14,backgroundColor:'#202126',flexDirection:'row',alignItems:'center'},error:{marginTop:16,padding:14,borderRadius:14,backgroundColor:'#fee2e2'},result:{marginTop:18,padding:12,borderRadius:18},resultImage:{width:'100%',height:330,borderRadius:14},open:{paddingVertical:16,alignItems:'center'},openText:{color:'#2563eb',fontSize:17,fontWeight:'900'},chatResult:{marginTop:18,padding:16,borderRadius:18},task:{marginTop:18,padding:16,borderRadius:18},historyHead:{flexDirection:'row',alignItems:'center',justifyContent:'space-between',marginBottom:16},blue:{color:'#2563eb',fontWeight:'900'},historyCard:{padding:14,borderRadius:18,marginBottom:10,flexDirection:'row',gap:12,alignItems:'center'},historyIcon:{width:40,height:40,borderRadius:14,backgroundColor:'#25262B',color:'#fff',fontSize:20,textAlign:'center',textAlignVertical:'center'},sheetBackdrop:{flex:1,backgroundColor:'rgba(0,0,0,.62)',justifyContent:'flex-end'},sheet:{borderTopLeftRadius:30,borderTopRightRadius:30,padding:18,paddingBottom:28},sheetHandle:{width:42,height:5,borderRadius:3,backgroundColor:'#55565B',alignSelf:'center',marginBottom:16},sheetHeader:{flexDirection:'row',justifyContent:'space-between',alignItems:'center'},sheetTitle:{fontSize:23,fontWeight:'900'},search:{height:48,borderRadius:16,paddingHorizontal:14,marginTop:14,fontSize:14},modePills:{flexDirection:'row',gap:7,marginVertical:12},pill:{paddingHorizontal:13,paddingVertical:9,borderRadius:18},modelRow:{minHeight:66,borderRadius:17,padding:10,marginBottom:7,flexDirection:'row',alignItems:'center'},modelLogoSmall:{width:38,height:38,borderRadius:12,backgroundColor:'#292A2F',alignItems:'center',justifyContent:'center',marginRight:11},custom:{marginTop:10,padding:12,borderRadius:17},customInput:{height:43,borderWidth:1,borderColor:'#3A3B40',borderRadius:12,paddingHorizontal:11,marginTop:8},customButton:{marginTop:8,backgroundColor:'#F4F4F5',borderRadius:12,paddingVertical:11,alignItems:'center'}
});
