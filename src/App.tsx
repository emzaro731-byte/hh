import React,{useEffect,useState}from'react';
import{ActivityIndicator,Pressable,SafeAreaView,StyleSheet,Text,View}from'react-native';
import{Session}from'@supabase/supabase-js';
import{supabase}from'./lib/supabase';
import AuthScreen from'./screens/AuthScreen';
import PremiumMessengerHome from'./PremiumMessengerHome';
import AIStudio from'./screens/AIStudio';
import{setupCallNotifications,registerPushToken,watchPushTokenRefresh}from'./lib/push';

export default function App(){
 const[session,setSession]=useState<Session|null>(null),[loading,setLoading]=useState(true),[aiVisible,setAiVisible]=useState(false);
 useEffect(()=>{let mounted=true;supabase.auth.getSession().then(({data})=>{if(mounted){setSession(data.session);setLoading(false)}});const{data:listener}=supabase.auth.onAuthStateChange((_event,next)=>setSession(next));return()=>{mounted=false;listener.subscription.unsubscribe()}},[]);
 useEffect(()=>{if(!session)return;let unsub:(()=>void)|undefined;setupCallNotifications().then(()=>registerPushToken()).catch(e=>console.warn('Push setup failed',e));unsub=watchPushTokenRefresh();return()=>unsub?.()},[session]);
 if(loading)return <SafeAreaView style={styles.safe}><View style={styles.center}><ActivityIndicator size="large"/></View></SafeAreaView>;
 if(!session)return <AuthScreen onAuthenticated={()=>undefined}/>;
 return <View style={styles.app}>
  <PremiumMessengerHome/>
  <Pressable accessibilityRole="button" accessibilityLabel="Open GG AI" onPress={()=>setAiVisible(true)} style={styles.aiFab}>
   <View style={styles.aiGlow}><Text style={styles.aiRobot}>✦</Text><Text style={styles.aiText}>AI</Text></View>
  </Pressable>
  <View pointerEvents="none" style={styles.aiHint}><Text style={styles.aiHintTitle}>Chat with AI</Text><Text style={styles.aiHintText}>Ask, create, summarize and more</Text></View>
  <AIStudio visible={aiVisible} onClose={()=>setAiVisible(false)}/>
 </View>;
}
const styles=StyleSheet.create({safe:{flex:1,backgroundColor:'#090B10'},app:{flex:1,backgroundColor:'#090B10'},center:{flex:1,alignItems:'center',justifyContent:'center'},aiFab:{position:'absolute',right:24,bottom:158,width:78,height:78,borderRadius:39,backgroundColor:'#101820',borderWidth:3,borderColor:'#22d3ee',alignItems:'center',justifyContent:'center',elevation:14,shadowColor:'#22d3ee',shadowOpacity:.55,shadowRadius:14,shadowOffset:{width:0,height:0}},aiGlow:{width:64,height:64,borderRadius:32,borderWidth:2,borderColor:'#7c3aed',alignItems:'center',justifyContent:'center',backgroundColor:'#111827'},aiRobot:{color:'#67e8f9',fontSize:25,fontWeight:'900',lineHeight:27},aiText:{color:'#fff',fontSize:15,fontWeight:'900',marginTop:0},aiHint:{position:'absolute',right:22,bottom:242,width:190,borderRadius:14,borderWidth:1,borderColor:'#22d3ee',backgroundColor:'#111820',paddingHorizontal:14,paddingVertical:10},aiHintTitle:{color:'#fff',fontSize:15,fontWeight:'900'},aiHintText:{color:'#b7c2cc',fontSize:11,lineHeight:15,marginTop:2}});
