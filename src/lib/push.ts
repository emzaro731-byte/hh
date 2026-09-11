import {Platform} from 'react-native';
import messaging from '@react-native-firebase/messaging';
import notifee,{AndroidCategory,AndroidImportance,EventType} from '@notifee/react-native';
import {supabase} from './supabase';

export const CALL_CHANNEL_ID='gg-incoming-calls';

export async function setupCallNotifications(){
  await notifee.requestPermission();
  if(Platform.OS==='android'){
    await notifee.createChannel({
      id:CALL_CHANNEL_ID,
      name:'Incoming calls',
      importance:AndroidImportance.HIGH,
      sound:'default',
      vibration:true,
      bypassDnd:true,
    });
  }
}

export async function registerPushToken(){
  const permission=await messaging().hasPermission();
  if(permission===0)return null;
  const token=await messaging().getToken();
  const {data:{user}}=await supabase.auth.getUser();
  if(!user||!token)return null;
  const {error}=await supabase.from('device_tokens').upsert({
    user_id:user.id,
    token,
    platform:Platform.OS,
    updated_at:new Date().toISOString(),
  },{onConflict:'token'});
  if(error)throw error;
  return token;
}

export function watchPushTokenRefresh(){
  return messaging().onTokenRefresh(async token=>{
    const {data:{user}}=await supabase.auth.getUser();
    if(!user)return;
    await supabase.from('device_tokens').upsert({user_id:user.id,token,platform:Platform.OS,updated_at:new Date().toISOString()},{onConflict:'token'});
  });
}

export async function showIncomingCallNotification(data:{callId:string;callerName:string;callType:'audio'|'video'}){
  await setupCallNotifications();
  return notifee.displayNotification({
    title:`Incoming ${data.callType==='video'?'video':'voice'} call`,
    body:`${data.callerName} is calling you`,
    data:{type:'incoming_call',callId:data.callId,callerName:data.callerName,callType:data.callType},
    android:{
      channelId:CALL_CHANNEL_ID,
      category:AndroidCategory.CALL,
      importance:AndroidImportance.HIGH,
      sound:'default',
      vibrationPattern:[300,500,300,500,300,700],
      pressAction:{id:'default',launchActivity:'default'},
      fullScreenAction:{id:'default'},
      ongoing:true,
      autoCancel:false,
      actions:[
        {title:'Decline',pressAction:{id:'decline'}},
        {title:'Answer',pressAction:{id:'answer'}},
      ],
    },
  });
}

export function watchNotificationEvents(onCall:(data:any)=>void){
  return notifee.onForegroundEvent(async({type,detail})=>{
    if(type===EventType.PRESS||type===EventType.ACTION_PRESS){
      const data=detail.notification?.data;
      if(data?.type==='incoming_call')onCall({...data,action:detail.pressAction?.id||'default'});
    }
  });
}

export async function getInitialCallNotification(){
  const initial=await notifee.getInitialNotification();
  const data=initial?.notification?.data;
  return data?.type==='incoming_call'?data:null;
}
