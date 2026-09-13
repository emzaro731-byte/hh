import React,{useEffect,useState}from'react';
import{Pressable,SafeAreaView,StatusBar,StyleSheet,Text,TextInput,View}from'react-native';

type StatusItem={name:string;initial:string;caption?:string;time?:string;tone?:string};
type Props={items:StatusItem[];startIndex:number;onClose:()=>void};

export default function StatusViewer({items,startIndex,onClose}:Props){
 const[index,setIndex]=useState(startIndex),[reply,setReply]=useState('');
 const item=items[index]||items[0];
 useEffect(()=>{setReply('')},[index]);
 const next=()=>index<items.length-1?setIndex(index+1):onClose();
 const prev=()=>index>0&&setIndex(index-1);
 return <SafeAreaView style={s.safe}>
  <StatusBar barStyle="light-content" backgroundColor="#000"/>
  <View style={s.viewer}>
   <View style={s.progress}>{items.map((_,i)=><View key={i} style={[s.progressTrack,i<=index&&s.progressDone]}/>)}</View>
   <View style={s.top}>
    <Pressable onPress={onClose} hitSlop={12}><Text style={s.back}>‹</Text></Pressable>
    <View style={[s.avatar,{backgroundColor:item.tone||'#263238'}]}><Text style={s.avatarText}>{item.initial}</Text></View>
    <View style={s.user}><Text style={s.name}>{item.name}</Text><Text style={s.time}>{item.time||'18h'}  ·  ↪ Reshared</Text></View>
    <Pressable hitSlop={12}><Text style={s.more}>⋮</Text></Pressable>
   </View>
   <Pressable style={s.media} onPress={next} onLongPress={()=>{}}>
    <View style={[s.mediaGlow,{backgroundColor:item.tone||'#26352b'}]} />
    <Text style={s.mediaInitial}>{item.initial}</Text>
    <Text style={s.caption}>{item.caption||'Sometimes life is just not fair.'}</Text>
   </Pressable>
   <View style={s.bottomArea}>
    <Text style={s.dots}>•••</Text>
    <View style={s.actions}>
     <View style={s.replyBox}><TextInput value={reply} onChangeText={setReply} placeholder="Reply" placeholderTextColor="#eef2f3" style={s.reply}/></View>
     <Pressable style={s.round} onPress={()=>{}}><Text style={s.actionIcon}>😍</Text></Pressable>
     <Pressable style={s.round} onPress={()=>{}}><Text style={s.actionIcon}>😂</Text></Pressable>
     <Pressable style={s.round} onPress={()=>{}}><Text style={s.actionIcon}>↪</Text></Pressable>
     <Pressable style={s.round} onPress={()=>{}}><Text style={s.actionIcon}>♡</Text></Pressable>
    </View>
   </View>
   <Pressable style={s.leftZone} onPress={prev}/><Pressable style={s.rightZone} onPress={next}/>
  </View>
 </SafeAreaView>
}
const s=StyleSheet.create({safe:{flex:1,backgroundColor:'#000'},viewer:{flex:1,backgroundColor:'#05080a'},progress:{position:'absolute',zIndex:5,top:10,left:8,right:8,height:4,flexDirection:'row',gap:7},progressTrack:{flex:1,height:4,borderRadius:4,backgroundColor:'#666'},progressDone:{backgroundColor:'#fff'},top:{position:'absolute',zIndex:5,top:27,left:18,right:18,height:65,flexDirection:'row',alignItems:'center'},back:{color:'#fff',fontSize:58,fontWeight:'200',lineHeight:54,width:55},avatar:{width:54,height:54,borderRadius:27,borderWidth:2,borderColor:'#fff',alignItems:'center',justifyContent:'center'},avatarText:{color:'#fff',fontSize:19,fontWeight:'900'},user:{flex:1,marginLeft:12},name:{color:'#fff',fontSize:23,fontWeight:'900'},time:{color:'#f1f3f4',fontSize:15,fontWeight:'700',marginTop:2},more:{color:'#fff',fontSize:38,fontWeight:'900'},media:{position:'absolute',top:94,bottom:150,left:0,right:0,overflow:'hidden',alignItems:'center',justifyContent:'center'},mediaGlow:{position:'absolute',width:'140%',height:'120%',opacity:.92},mediaInitial:{color:'rgba(255,255,255,.16)',fontSize:190,fontWeight:'900'},caption:{position:'absolute',bottom:'28%',left:30,right:30,color:'#fff',fontSize:27,fontWeight:'900',textAlign:'center',textShadowColor:'#000',textShadowRadius:8},bottomArea:{position:'absolute',left:0,right:0,bottom:10,paddingHorizontal:17},dots:{color:'#fff',textAlign:'center',fontSize:24,letterSpacing:3,marginBottom:17},actions:{flexDirection:'row',alignItems:'center',gap:9},replyBox:{height:59,borderRadius:30,backgroundColor:'#1b252a',flex:1,justifyContent:'center',paddingHorizontal:18,borderWidth:1,borderColor:'#2b363b'},reply:{color:'#fff',fontSize:18,fontWeight:'700'},round:{width:60,height:60,borderRadius:30,backgroundColor:'#1d282e',alignItems:'center',justifyContent:'center'},actionIcon:{fontSize:26,color:'#fff'},leftZone:{position:'absolute',left:0,top:100,bottom:170,width:'27%'},rightZone:{position:'absolute',right:0,top:100,bottom:170,width:'27%'}});