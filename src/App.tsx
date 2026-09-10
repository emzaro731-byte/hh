import React, {useEffect, useState} from 'react';
import {Alert, FlatList, Pressable, SafeAreaView, StyleSheet, Text, TextInput, View} from 'react-native';
import messaging from '@react-native-firebase/messaging';
import AsyncStorage from '@react-native-async-storage/async-storage';

const SUPABASE_URL = process.env.SUPABASE_URL ?? '';
const SUPABASE_KEY = process.env.SUPABASE_PUBLISHABLE_KEY ?? '';

const demoChats = [
  {id: '1', name: 'GG Messenger', message: 'Welcome to your native messenger', time: 'Now'},
  {id: '2', name: 'New conversation', message: 'Start chatting securely', time: ''},
];

export default function App() {
  const [query, setQuery] = useState('');
  const [selected, setSelected] = useState<string | null>(null);
  const [message, setMessage] = useState('');
  const [messages, setMessages] = useState<string[]>([]);

  useEffect(() => {
    AsyncStorage.setItem('gg_native_boot', new Date().toISOString());
    messaging().requestPermission().catch(() => undefined);
    messaging().getToken().then(token => {
      if (token) AsyncStorage.setItem('gg_fcm_token', token);
    }).catch(() => undefined);
    const unsubscribe = messaging().onMessage(async remoteMessage => {
      Alert.alert(remoteMessage.notification?.title ?? 'GG Messenger', remoteMessage.notification?.body ?? 'New message');
    });
    return unsubscribe;
  }, []);

  if (selected) {
    return (
      <SafeAreaView style={styles.safe}>
        <View style={styles.header}>
          <Pressable onPress={() => setSelected(null)}><Text style={styles.back}>‹</Text></Pressable>
          <View><Text style={styles.title}>{selected}</Text><Text style={styles.subtitle}>online</Text></View>
        </View>
        <FlatList
          style={styles.messages}
          data={messages}
          keyExtractor={(_, i) => String(i)}
          renderItem={({item}) => <View style={styles.bubble}><Text style={styles.bubbleText}>{item}</Text></View>}
          ListEmptyComponent={<Text style={styles.empty}>No messages yet. Say hello 👋</Text>}
        />
        <View style={styles.composer}>
          <TextInput value={message} onChangeText={setMessage} placeholder="Message" style={styles.input} />
          <Pressable style={styles.send} onPress={() => { if (message.trim()) { setMessages(v => [...v, message.trim()]); setMessage(''); } }}><Text style={styles.sendText}>➤</Text></Pressable>
        </View>
      </SafeAreaView>
    );
  }

  const filtered = demoChats.filter(c => c.name.toLowerCase().includes(query.toLowerCase()));
  return (
    <SafeAreaView style={styles.safe}>
      <View style={styles.top}><View><Text style={styles.brand}>GG</Text><Text style={styles.subtitle}>Messenger</Text></View><Pressable onPress={() => Alert.alert('GG Messenger', 'Native React Native build initialized.')}><Text style={styles.more}>⋮</Text></Pressable></View>
      <TextInput value={query} onChangeText={setQuery} placeholder="Search chats" style={styles.search} />
      <FlatList
        data={filtered}
        keyExtractor={item => item.id}
        renderItem={({item}) => (
          <Pressable style={styles.chat} onPress={() => setSelected(item.name)}>
            <View style={styles.avatar}><Text style={styles.avatarText}>{item.name.slice(0,1)}</Text></View>
            <View style={styles.chatBody}><Text style={styles.chatName}>{item.name}</Text><Text style={styles.chatMessage}>{item.message}</Text></View><Text style={styles.time}>{item.time}</Text>
          </Pressable>
        )}
      />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe:{flex:1,backgroundColor:'#fff'}, top:{padding:20,flexDirection:'row',justifyContent:'space-between',alignItems:'center'},brand:{fontSize:30,fontWeight:'800'},title:{fontSize:18,fontWeight:'700'},subtitle:{color:'#6b7280',fontSize:12},more:{fontSize:28},search:{marginHorizontal:16,marginBottom:8,backgroundColor:'#f1f3f5',borderRadius:14,paddingHorizontal:16,paddingVertical:12,fontSize:16},chat:{padding:16,flexDirection:'row',alignItems:'center',borderBottomWidth:StyleSheet.hairlineWidth,borderBottomColor:'#ddd'},avatar:{width:50,height:50,borderRadius:25,backgroundColor:'#111827',alignItems:'center',justifyContent:'center'},avatarText:{color:'#fff',fontWeight:'700',fontSize:18},chatBody:{flex:1,marginLeft:12},chatName:{fontSize:16,fontWeight:'700'},chatMessage:{marginTop:4,color:'#6b7280'},time:{color:'#9ca3af',fontSize:12},header:{padding:16,flexDirection:'row',alignItems:'center',gap:12,borderBottomWidth:StyleSheet.hairlineWidth,borderBottomColor:'#ddd'},back:{fontSize:38,lineHeight:32},messages:{flex:1,padding:16},empty:{textAlign:'center',marginTop:40,color:'#777'},bubble:{alignSelf:'flex-end',backgroundColor:'#111827',borderRadius:18,padding:12,marginBottom:8,maxWidth:'80%'},bubbleText:{color:'#fff',fontSize:16},composer:{flexDirection:'row',padding:10,borderTopWidth:StyleSheet.hairlineWidth,borderTopColor:'#ddd',alignItems:'center'},input:{flex:1,backgroundColor:'#f1f3f5',borderRadius:22,paddingHorizontal:16,paddingVertical:10},send:{marginLeft:8,width:44,height:44,borderRadius:22,backgroundColor:'#111827',alignItems:'center',justifyContent:'center'},sendText:{color:'#fff',fontSize:20}
});
