const fs = require('fs');
const path = require('path');

const file = path.join(process.cwd(), 'src', 'MessengerHome.tsx');
if (!fs.existsSync(file)) process.exit(0);
let s = fs.readFileSync(file, 'utf8');

if (!s.includes("react-native-nitro-sound")) {
  s = s.replace(
    "import{Alert,FlatList,Image,KeyboardAvoidingView,Modal,Platform,Pressable,SafeAreaView,StatusBar,StyleSheet,Text,TextInput,View}from'react-native';",
    "import{Alert,FlatList,Image,KeyboardAvoidingView,Modal,PermissionsAndroid,Platform,Pressable,SafeAreaView,StatusBar,StyleSheet,Text,TextInput,View}from'react-native';"
  );
  s = s.replace(
    "import{supabase}from'./lib/supabase';",
    "import{supabase}from'./lib/supabase';\nimport Sound from'react-native-nitro-sound';"
  );
}

if (!s.includes("[recording,setRecording]")) {
  s = s.replace(
    "[menu,setMenu]=useState<Message|null>(null),[activeCall,setActiveCall]=useState<any>(null);",
    "[menu,setMenu]=useState<Message|null>(null),[activeCall,setActiveCall]=useState<any>(null),[recording,setRecording]=useState(false),[recordingLoading,setRecordingLoading]=useState(false),[playingId,setPlayingId]=useState<string|null>(null);"
  );
}

if (!s.includes('async function recordVoice()')) {
  const marker = " const bubble=(m:Message)=>";
  const voice = ` async function requestMic(){if(Platform.OS!=='android')return true;try{const g=await PermissionsAndroid.request(PermissionsAndroid.PERMISSIONS.RECORD_AUDIO,{title:'Microphone permission',message:'GG needs your microphone to record voice messages.',buttonNeutral:'Ask Me Later',buttonNegative:'Cancel',buttonPositive:'OK'});return g===PermissionsAndroid.RESULTS.GRANTED}catch{return false}}\n async function uploadVoice(recordingPath:string){if(!selected)return;try{const uri=recordingPath.startsWith('file://')?recordingPath:'file://'+recordingPath;const blob=await fetch(uri).then(x=>x.blob());const name=\`voice-\${Date.now()}.mp4\`,storagePath=\`\${userId}/\${name}\`,up=await supabase.storage.from('chat-media').upload(storagePath,blob,{contentType:'audio/mp4',upsert:false});if(up.error)throw up.error;const signed=await supabase.storage.from('chat-media').createSignedUrl(storagePath,604800);if(signed.error)throw signed.error;const m=await sendMediaMessage(selected.id,signed.data.signedUrl,'voice',name);setMessages(v=>[...v,m])}catch(e){Alert.alert('Voice message failed',String(e))}}\n async function recordVoice(){if(!selected||recordingLoading)return;if(recording){setRecordingLoading(true);try{const p=await Sound.stopRecorder();Sound.removeRecordBackListener();setRecording(false);if(p&&p!=='recorder already stopped')await uploadVoice(p)}catch(e){setRecording(false);Alert.alert('Recording failed',String(e))}finally{setRecordingLoading(false)}return}const ok=await requestMic();if(!ok){Alert.alert('Microphone permission','Allow GG to use the microphone to record voice messages.');return}setRecordingLoading(true);try{await Sound.startRecorder(undefined,{AudioSamplingRate:44100,AudioEncodingBitRate:128000,AudioChannels:1},true);setRecording(true)}catch(e){Alert.alert('Recording failed',String(e))}finally{setRecordingLoading(false)}}\n async function playVoice(m:Message){if(!m.media_url)return;try{if(playingId===m.id){await Sound.stopPlayer();setPlayingId(null);return}await Sound.stopPlayer().catch(()=>{});Sound.removePlaybackEndListener();Sound.addPlaybackEndListener(()=>setPlayingId(null));await Sound.startPlayer(m.media_url);setPlayingId(m.id)}catch(e){Alert.alert('Audio playback failed',String(e))}\n }\n`;
  s = s.replace(marker, voice + marker);
}

s = s.replace(
  ":m.message_type==='file'?<Text style={{color:fg,fontWeight:'700'}}>📄 {m.file_name||'Document'}</Text>:<Text style={{color:fg,fontSize:15,lineHeight:21}}>{m.body}</Text>",
  ":m.message_type==='file'?<Text style={{color:fg,fontWeight:'700'}}>📄 {m.file_name||'Document'}</Text>:m.message_type==='voice'?<Pressable onPress={()=>playVoice(m)} style={s.voice}><Text style={{fontSize:22}}>{playingId===m.id?'⏹':'▶'}</Text><Text style={{color:fg,fontWeight:'800'}}>{playingId===m.id?'Playing voice':'Voice message'}</Text></Pressable>:<Text style={{color:fg,fontSize:15,lineHeight:21}}>{m.body}</Text>"
);

s = s.replace(
  "<Pressable onPress={send} style={s.send}><Text style={{color:'#fff',fontSize:18}}>{text.trim()?'➤':'🎙'}</Text></Pressable>",
  "<Pressable onPress={text.trim()?send:recordVoice} disabled={recordingLoading} style={[s.send,recording&&{backgroundColor:'#e53935'}]}><Text style={{color:'#fff',fontSize:18}}>{recording?'■':text.trim()?'➤':'🎙'}</Text></Pressable>"
);

s = s.replace(
  "<Pressable onPress={()=>{setAttach(false);Alert.alert('Audio','Native voice recording can be enabled next.')}} style={s.attach}><Text style={s.attachIcon}>🎙️</Text><Text style={{color:fg}}>Audio</Text></Pressable>",
  "<Pressable onPress={()=>{setAttach(false);recordVoice()}} style={s.attach}><Text style={s.attachIcon}>🎙️</Text><Text style={{color:fg}}>Voice</Text></Pressable>"
);

if (!s.includes("voice:{")) {
  s = s.replace(
    "media:{width:230,height:220,borderRadius:7},video:{",
    "media:{width:230,height:220,borderRadius:7},voice:{minWidth:180,minHeight:48,borderRadius:24,paddingHorizontal:14,flexDirection:'row',alignItems:'center',gap:10},video:{"
  );
}

fs.writeFileSync(file, s);
console.log('Voice recording patch applied to src/MessengerHome.tsx');
