import React,{useEffect,useRef,useState}from'react';
import{Alert,Pressable,SafeAreaView,StyleSheet,Text,Vibration,View}from'react-native';
import{mediaDevices,RTCIceCandidate,RTCPeerConnection,RTCSessionDescription,RTCView}from'react-native-webrtc';
import{Call,CallRole,CallType,getCall,loadCallSignals,sendCallSignal,setCallStatus,subscribeToCall}from'../lib/calls';
import{supabase}from'../lib/supabase';

type Props={callId:string;peerName:string;type:CallType;role:CallRole;incoming?:boolean;onClose:()=>void};
const config={iceServers:[{urls:'stun:stun.l.google.com:19302'},{urls:'stun:stun1.l.google.com:19302'}]};

export default function CallScreen({callId,peerName,type,role,incoming=false,onClose}:Props){
 const pc=useRef<RTCPeerConnection|null>(null),channel=useRef<any>(null),pendingCandidates=useRef<any[]>([]),ringTimer=useRef<any>(null);
 const[local,setLocal]=useState<any>(null),[remote,setRemote]=useState<any>(null),[connected,setConnected]=useState(false),[accepted,setAccepted]=useState(!incoming),[muted,setMuted]=useState(false),[camera,setCamera]=useState(type==='video'),[pulse,setPulse]=useState(false),[ringing,setRinging]=useState(true);

 // Keep the call screen visibly and physically ringing until the call is answered/ended.
 useEffect(()=>{
  if(!ringing)return;
  Vibration.vibrate([0,500,300,500],true);
  ringTimer.current=setInterval(()=>setPulse(v=>!v),700);
  return()=>{Vibration.cancel();if(ringTimer.current)clearInterval(ringTimer.current)};
 },[ringing]);

 useEffect(()=>()=>{if(channel.current)supabase.removeChannel(channel.current);pc.current?.close();local?.getTracks?.().forEach((t:any)=>t.stop());Vibration.cancel()},[local]);
 useEffect(()=>{if(accepted)void start();},[accepted]);
 async function start(){
  try{
   const stream=await mediaDevices.getUserMedia({audio:true,video:camera?{facingMode:'user'}:false});
   setLocal(stream);
   const peer=new RTCPeerConnection(config as any);pc.current=peer;
   stream.getTracks().forEach((track:any)=>peer.addTrack(track,stream));
   peer.ontrack=(event:any)=>{if(event.streams?.[0]){setRemote(event.streams[0]);setConnected(true);setRinging(false)}};
   peer.onconnectionstatechange=()=>{const state=peer.connectionState;if(state==='connected'){setConnected(true);setRinging(false)}if(['failed','closed'].includes(state))onClose()};
   peer.onicecandidate=(event:any)=>{if(event.candidate)void sendCallSignal(callId,'candidate',event.candidate.toJSON?.()??event.candidate)};
   channel.current=subscribeToCall(callId,async(next:Call)=>{if(next.status==='active'){setConnected(true);setRinging(false)}if(next.status==='ended'||next.status==='rejected'){setRinging(false);onClose()}},async(signal:any)=>{
    const current=await getCall(callId).catch(()=>null);if(!current)return;
    if((role==='caller'&&signal.sender_id===current.caller_id)||(role==='callee'&&signal.sender_id===current.callee_id))return;
    try{
      if(signal.kind==='offer'&&role==='callee'){
       await peer.setRemoteDescription(new RTCSessionDescription(signal.payload));
       for(const c of pendingCandidates.current)await peer.addIceCandidate(new RTCIceCandidate(c)).catch(()=>{});pendingCandidates.current=[];
       const answer=await peer.createAnswer();await peer.setLocalDescription(answer);await sendCallSignal(callId,'answer',answer);await setCallStatus(callId,'active');setRinging(false);
      }else if(signal.kind==='answer'&&role==='caller'){
       await peer.setRemoteDescription(new RTCSessionDescription(signal.payload));
       for(const c of pendingCandidates.current)await peer.addIceCandidate(new RTCIceCandidate(c)).catch(()=>{});pendingCandidates.current=[];setRinging(false);
      }else if(signal.kind==='candidate'){
       const candidate=new RTCIceCandidate(signal.payload);if(peer.remoteDescription)await peer.addIceCandidate(candidate).catch(()=>{});else pendingCandidates.current.push(signal.payload);
      }
    }catch(e){console.warn('call signal',e)}
   });
   const existing=await loadCallSignals(callId);
   if(role==='caller'){
    const offer=await peer.createOffer({});await peer.setLocalDescription(offer);await sendCallSignal(callId,'offer',offer);await setCallStatus(callId,'ringing');
   }else{
    const offer=existing.find((x:any)=>x.kind==='offer');
    if(offer){await peer.setRemoteDescription(new RTCSessionDescription(offer.payload));const answer=await peer.createAnswer();await peer.setLocalDescription(answer);await sendCallSignal(callId,'answer',answer);await setCallStatus(callId,'active');setRinging(false)}
   }
  }catch(e){setRinging(false);Alert.alert('Call failed',e instanceof Error?e.message:'Could not start the call');onClose()}
 }
 async function end(notify=true){setRinging(false);if(notify)await setCallStatus(callId,'ended').catch(()=>{});local?.getTracks?.().forEach((t:any)=>t.stop());pc.current?.close();Vibration.cancel();onClose()}
 function toggleMute(){local?.getAudioTracks?.().forEach((t:any)=>t.enabled=!t.enabled);setMuted(v=>!v)}
 function toggleCamera(){local?.getVideoTracks?.().forEach((t:any)=>t.enabled=!t.enabled);setCamera(v=>!v)}
 async function reject(){setRinging(false);await setCallStatus(callId,'rejected').catch(()=>{});onClose()}
 const incomingWaiting=incoming&&!accepted;
 return <SafeAreaView style={s.safe}>
  <View style={s.stage}>{remote&&type==='video'?<RTCView streamURL={remote.toURL()} style={s.remote} objectFit="cover"/>:<View style={s.placeholder}>
    <View style={[s.avatarRing,pulse&&s.avatarRingPulse]}><Text style={s.avatar}>{peerName[0]?.toUpperCase()||'G'}</Text></View>
    <Text style={s.name}>{peerName}</Text>
    <Text style={s.state}>{connected?'Connected':incomingWaiting?'Incoming call…':ringing?'Ringing…':type==='video'?'Video call':'Voice call'}</Text>
    {ringing&&!connected&&<Text style={s.ringHint}>{type==='video'?'📹 Video calling':'☎ Calling'}</Text>}
   </View>}
   {local&&type==='video'&&<RTCView streamURL={local.toURL()} style={s.local} objectFit="cover"/>}
   <View style={s.top}><Text style={s.peer}>{peerName}</Text><Text style={s.kind}>{type==='video'?'Video call':'Voice call'}</Text></View>
   {incomingWaiting?<View style={s.incoming}><Pressable style={s.reject} onPress={reject}><Text style={s.btnText}>Decline</Text></Pressable><Pressable style={s.accept} onPress={()=>{setRinging(false);setAccepted(true)}}><Text style={s.btnText}>Accept</Text></Pressable></View>:<View style={s.controls}><Pressable style={s.control} onPress={toggleMute}><Text style={s.controlText}>{muted?'🔇':'🎙️'}</Text></Pressable>{type==='video'&&<Pressable style={s.control} onPress={toggleCamera}><Text style={s.controlText}>{camera?'📷':'🚫'}</Text></Pressable>}<Pressable style={s.hangup} onPress={()=>end()}><Text style={s.controlText}>☎</Text></Pressable></View>}
  </View>
 </SafeAreaView>
}
const s=StyleSheet.create({safe:{flex:1,backgroundColor:'#05070b'},stage:{flex:1,position:'relative',justifyContent:'center',alignItems:'center'},remote:{...StyleSheet.absoluteFillObject},local:{position:'absolute',right:18,top:70,width:105,height:150,borderRadius:14},placeholder:{alignItems:'center'},avatarRing:{width:124,height:124,borderRadius:62,borderWidth:3,borderColor:'#2563eb',alignItems:'center',justifyContent:'center'},avatarRingPulse:{transform:[{scale:1.08}],opacity:.78},avatar:{width:100,height:100,borderRadius:50,backgroundColor:'#172033',color:'#fff',fontSize:40,fontWeight:'900',textAlign:'center',textAlignVertical:'center'},name:{color:'#fff',fontSize:25,fontWeight:'900',marginTop:20},state:{color:'#aab4c4',marginTop:8,fontSize:16},ringHint:{color:'#60a5fa',marginTop:10,fontSize:15,fontWeight:'800'},top:{position:'absolute',top:25,left:20,right:20},peer:{color:'#fff',fontSize:20,fontWeight:'800'},kind:{color:'#9ca3af',marginTop:3},controls:{position:'absolute',bottom:35,flexDirection:'row',alignItems:'center',gap:18},control:{width:58,height:58,borderRadius:29,backgroundColor:'#263142',alignItems:'center',justifyContent:'center'},hangup:{width:64,height:64,borderRadius:32,backgroundColor:'#ef4444',alignItems:'center',justifyContent:'center'},controlText:{fontSize:24},incoming:{position:'absolute',bottom:40,flexDirection:'row',gap:20},accept:{backgroundColor:'#22c55e',paddingHorizontal:28,paddingVertical:16,borderRadius:28},reject:{backgroundColor:'#ef4444',paddingHorizontal:28,paddingVertical:16,borderRadius:28},btnText:{color:'#fff',fontSize:16,fontWeight:'800'}});
