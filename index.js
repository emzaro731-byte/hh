import {AppRegistry} from 'react-native';
import messaging from '@react-native-firebase/messaging';
import App from './src/App';
import {name as appName} from './app.json';

messaging().setBackgroundMessageHandler(async remoteMessage => {
  console.log('GG background message:', remoteMessage.messageId);
});

AppRegistry.registerComponent(appName, () => App);
