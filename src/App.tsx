import React,{useEffect,useState}from'react';
import{ActivityIndicator,Pressable,SafeAreaView,StyleSheet,Text,View}from'react-native';
import{Session}from'@supabase/supabase-js';
import{supabase}from'./lib/supabase';
import AuthScreen from'./screens/AuthScreen';
import MessengerHome from'./MessengerHome';
import AIStudio from'./screens/AIStudio';
import{setupCallNotifications,registerPushToken,watchPushTokenRefresh}from'./lib/push';

export default function App(){
 const[session,setSession]=useState<Session|null>(null),[loading,setLoading]=useState(true),[aiOpen,setAiOpen]=useState(false),[dark,setDark]=useState(false);
 useEffect(()=>{
  let mounted=true;
  supabase.auth.getSession().then(({data})=>{if(mounted){setSession(data.session);setLoading(false)}});
  const{data:listener}=supabase.auth.onAuthStateChange((_event,next)=>setSession(next));
  return()=>{mounted=false;listener.subscription.unsubscribe()};
 },[]);
 useEffect(()=>{
  if(!session)return;
  let unsub:(()=>void)|undefined;
  setupCallNotifications().then(()=>registerPushToken()).catch(e=>console.warn('Push setup failed',e));
  unsub=watchPushTokenRefresh();
  return()=>unsub?.();
 },[session]);
 if(loading)return <SafeAreaView style={styles.safe}><View style={styles.center}><ActivityIndicator size="large"/></View></SafeAreaView>;
 if(!session)return <AuthScreen onAuthenticated={()=>undefined}/>;
 return <View style={styles.app}><MessengerHome/><Pressable onPress={()=>setAiOpen(true)} style={styles.aiButton}><Text style={styles.aiIcon}>✦</Text><Text style={styles.aiText}>AI</Text></Pressable><AIStudio visible={aiOpen} onClose={()=>setAiOpen(false)} dark={dark}/></View>;
}
const styles=StyleSheet.create({safe:{flex:1,backgroundColor:'#f7f8fa'},center:{flex:1,alignItems:'center',justifyContent:'center'},app:{flex:1},aiButton:{position:'absolute',right:16,bottom:82,width:58,height:58,borderRadius:29,backgroundColor:'#2563eb',alignItems:'center',justifyContent:'center',elevation:8,shadowOpacity:.25,shadowRadius:8,shadowOffset:{width:0,height:3}},aiIcon:{color:'#fff',fontSize:20,fontWeight:'900'},aiText:{color:'#fff',fontSize:11,fontWeight:'900',marginTop:-2}});
