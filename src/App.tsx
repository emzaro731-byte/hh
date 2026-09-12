import React,{useEffect,useState}from'react';
import{ActivityIndicator,SafeAreaView,StyleSheet,View}from'react-native';
import{Session}from'@supabase/supabase-js';
import{supabase}from'./lib/supabase';
import AuthScreen from'./screens/AuthScreen';
import MessengerHome from'./MessengerHome';
import{setupCallNotifications,registerPushToken,watchPushTokenRefresh}from'./lib/push';

export default function App(){
 const[session,setSession]=useState<Session|null>(null),[loading,setLoading]=useState(true);
 useEffect(()=>{let mounted=true;supabase.auth.getSession().then(({data})=>{if(mounted){setSession(data.session);setLoading(false)}});const{data:listener}=supabase.auth.onAuthStateChange((_event,next)=>setSession(next));return()=>{mounted=false;listener.subscription.unsubscribe()}},[]);
 useEffect(()=>{if(!session)return;let unsub:(()=>void)|undefined;setupCallNotifications().then(()=>registerPushToken()).catch(e=>console.warn('Push setup failed',e));unsub=watchPushTokenRefresh();return()=>unsub?.()},[session]);
 if(loading)return <SafeAreaView style={styles.safe}><View style={styles.center}><ActivityIndicator size="large"/></View></SafeAreaView>;
 if(!session)return <AuthScreen onAuthenticated={()=>undefined}/>;
 return <MessengerHome/>;
}
const styles=StyleSheet.create({safe:{flex:1,backgroundColor:'#0b1115'},center:{flex:1,alignItems:'center',justifyContent:'center'}});
