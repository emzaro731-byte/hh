import {AppRegistry} from 'react-native';
import messaging from '@react-native-firebase/messaging';
import notifee from '@notifee/react-native';
import App from './src/App';
import {name as appName} from './app.json';

messaging().setBackgroundMessageHandler(async remoteMessage=>{
  const d=remoteMessage.data||{};
  if(d.type==='incoming_call'&&d.callId){
    const channelId=await notifee.createChannel({id:'gg-incoming-calls',name:'Incoming calls',importance:4,sound:'default',vibration:true,bypassDnd:true});
    await notifee.displayNotification({
      title:`Incoming ${d.callType==='video'?'video':'voice'} call`,
      body:`${d.callerName||'GG User'} is calling you`,
      data:d,
      android:{
        channelId,
        category:'call',
        importance:4,
        sound:'default',
        vibrationPattern:[300,500,300,500,300,700],
        ongoing:true,
        autoCancel:false,
        pressAction:{id:'default',launchActivity:'default'},
        fullScreenAction:{id:'default'},
        actions:[{title:'Decline',pressAction:{id:'decline'}},{title:'Answer',pressAction:{id:'answer'}}],
      },
    });
    return;
  }
  console.log('GG background message:',remoteMessage.messageId);
});

AppRegistry.registerComponent(appName,()=>App);
