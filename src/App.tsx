import React, {useEffect, useMemo, useState} from 'react';
import {Alert, FlatList, KeyboardAvoidingView, Platform, Pressable, SafeAreaView, StatusBar, StyleSheet, Text, TextInput, View} from 'react-native';
import messaging from '@react-native-firebase/messaging';
import AsyncStorage from '@react-native-async-storage/async-storage';
import {supabase} from './lib/supabase';
import {loadMessages, sendMessage, subscribeToMessages, Message} from './lib/chat';

type Chat = {id: string; name: string; message: string; time: string; unread?: number; online?: boolean};
const demoChats: Chat[] = [
  {id: '1', name: 'GG Messenger', message: 'Welcome to your new messenger ✨', time: 'Now', unread: 2, online: true},
  {id: '2', name: 'Alex Johnson', message: 'See you soon!', time: '10:42', online: true},
  {id: '3', name: 'Creative Team', message: 'New project files are ready', time: '09:18', unread: 5},
  {id: '4', name: 'Sarah', message: 'Voice message', time: 'Yesterday'},
];

export default function App() {
  const [tab, setTab] = useState('Chats');
  const [query, setQuery] = useState('');
  const [selected, setSelected] = useState<Chat | null>(null);
  const [message, setMessage] = useState('');
  const [messages, setMessages] = useState<Message[]>([]);
  const [localMessages, setLocalMessages] = useState<string[]>([]);
  const [dark, setDark] = useState(false);
  const [sending, setSending] = useState(false);

  useEffect(() => {
    AsyncStorage.setItem('gg_native_boot', new Date().toISOString());
    messaging().requestPermission().catch(() => undefined);
    messaging().getToken().then(token => token && AsyncStorage.setItem('gg_fcm_token', token)).catch(() => undefined);
    const unsubscribe = messaging().onMessage(async remoteMessage => Alert.alert(remoteMessage.notification?.title ?? 'GG Messenger', remoteMessage.notification?.body ?? 'New message'));
    return unsubscribe;
  }, []);

  useEffect(() => {
    if (!selected) return;
    let active = true;
    loadMessages(selected.id).then(data => active && setMessages(data)).catch(() => undefined);
    const channel = subscribeToMessages(selected.id, incoming => setMessages(current => current.some(m => m.id === incoming.id) ? current : [...current, incoming]));
    return () => { active = false; supabase.removeChannel(channel); };
  }, [selected]);

  const filtered = useMemo(() => demoChats.filter(c => c.name.toLowerCase().includes(query.toLowerCase())), [query]);
  const bg = dark ? '#090b10' : '#f7f8fa';
  const card = dark ? '#12151c' : '#ffffff';
  const text = dark ? '#f7f8ff' : '#111827';
  const muted = dark ? '#9aa3b2' : '#6b7280';

  async function handleSend() {
    const body = message.trim(); if (!body || !selected || sending) return;
    setSending(true); setMessage('');
    try { const sent = await sendMessage(selected.id, body); setMessages(v => v.some(m => m.id === sent.id) ? v : [...v, sent]); }
    catch { setLocalMessages(v => [...v, body]); }
    finally { setSending(false); }
  }

  if (selected) return (
    <SafeAreaView style={[styles.safe, {backgroundColor: bg}]}>
      <StatusBar barStyle={dark ? 'light-content' : 'dark-content'} />
      <KeyboardAvoidingView style={styles.flex} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        <View style={[styles.chatHeader, {backgroundColor: card}]}>
          <Pressable onPress={() => setSelected(null)} style={styles.iconButton}><Text style={[styles.icon, {color: text}]}>‹</Text></Pressable>
          <View style={styles.profileRow}><View style={styles.avatarLarge}><Text style={styles.avatarText}>{selected.name[0]}</Text><View style={styles.onlineDot}/></View><View><Text style={[styles.title, {color: text}]}>{selected.name}</Text><Text style={[styles.subtitle, {color: muted}]}>{selected.online ? 'online' : 'last seen recently'}</Text></View></View>
          <View style={styles.headerActions}><Pressable onPress={() => Alert.alert('Voice call','Calling '+selected.name)}><Text style={styles.actionIcon}>☎</Text></Pressable><Pressable onPress={() => Alert.alert('Video call','Starting video call with '+selected.name)}><Text style={styles.actionIcon}>▣</Text></Pressable></View>
        </View>
        <FlatList style={styles.messages} contentContainerStyle={styles.messageContent} data={messages.length ? messages : localMessages.map((body, i) => ({id:String(i), body, conversation_id:selected.id, sender_id:'me', created_at:new Date().toISOString()} as Message))} keyExtractor={m => m.id} renderItem={({item}) => <View style={styles.messageLine}><View style={[styles.bubble, {backgroundColor: dark ? '#293241' : '#172033'}]}><Text style={styles.bubbleText}>{item.body}</Text><Text style={styles.read}>✓✓</Text></View></View>} ListEmptyComponent={<View style={styles.emptyBox}><Text style={styles.emptyEmoji}>👋</Text><Text style={[styles.emptyTitle,{color:text}]}>Say hello</Text><Text style={[styles.empty,{color:muted}]}>Messages are private and delivered in real time.</Text></View>} />
        <View style={[styles.composer,{backgroundColor:card}]}><Pressable style={styles.plus}><Text style={styles.plusText}>＋</Text></Pressable><TextInput value={message} onChangeText={setMessage} placeholder="Write a message…" placeholderTextColor={muted} style={[styles.input,{backgroundColor:dark?'#20242d':'#f0f2f5',color:text}]} onSubmitEditing={handleSend}/><Pressable style={styles.send} onPress={handleSend}><Text style={styles.sendText}>{sending ? '…' : '➤'}</Text></Pressable></View>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );

  return (
    <SafeAreaView style={[styles.safe,{backgroundColor:bg}]}>
      <StatusBar barStyle={dark ? 'light-content' : 'dark-content'} />
      <View style={[styles.top,{backgroundColor:card}]}><View><Text style={[styles.brand,{color:text}]}>GG</Text><Text style={[styles.subtitle,{color:muted}]}>Messenger</Text></View><View style={styles.topActions}><Pressable onPress={() => Alert.alert('New message','Choose a contact to start a conversation.')} style={styles.circle}><Text style={[styles.circleText,{color:text}]}>＋</Text></Pressable><Pressable onPress={() => setDark(v => !v)} style={styles.circle}><Text style={[styles.circleText,{color:text}]}>{dark?'☀':'☾'}</Text></Pressable></View></View>
      <View style={[styles.hero,{backgroundColor:card}]}><Text style={[styles.greeting,{color:text}]}>Good evening 👋</Text><Text style={[styles.heroTitle,{color:text}]}>Stay connected.</Text><Text style={[styles.heroSub,{color:muted}]}>Your conversations, calls and moments in one place.</Text></View>
      <View style={styles.searchWrap}><Text style={styles.searchIcon}>⌕</Text><TextInput value={query} onChangeText={setQuery} placeholder="Search conversations" placeholderTextColor={muted} style={[styles.search,{color:text}]}/></View>
      <View style={styles.sectionRow}><Text style={[styles.sectionTitle,{color:text}]}>{tab === 'Chats' ? 'Recent chats' : tab}</Text><Pressable onPress={() => Alert.alert(tab, 'More options coming soon')}><Text style={styles.seeAll}>See all</Text></Pressable></View>
      {tab === 'Chats' && <FlatList data={filtered} keyExtractor={i=>i.id} contentContainerStyle={styles.list} renderItem={({item})=><Pressable style={[styles.chat,{backgroundColor:card}]} onPress={()=>setSelected(item)}><View style={styles.avatar}><Text style={styles.avatarText}>{item.name[0]}</Text>{item.online&&<View style={styles.onlineDot}/>}</View><View style={styles.chatBody}><View style={styles.chatNameRow}><Text style={[styles.chatName,{color:text}]}>{item.name}</Text><Text style={[styles.time,{color:muted}]}>{item.time}</Text></View><View style={styles.chatPreviewRow}><Text numberOfLines={1} style={[styles.chatMessage,{color:muted}]}>{item.message}</Text>{item.unread ? <View style={styles.badge}><Text style={styles.badgeText}>{item.unread}</Text></View> : null}</View></View></Pressable>}/>} 
      {tab === 'Calls' && <EmptyTab icon="☎" title="Your calls" text="Voice and video calls will appear here." />}
      {tab === 'Status' && <EmptyTab icon="◉" title="Share a moment" text="Post a status and keep friends updated." />}
      {tab === 'Profile' && <View style={[styles.profileCard,{backgroundColor:card}]}><View style={styles.profileAvatar}><Text style={styles.profileInitial}>G</Text></View><Text style={[styles.profileName,{color:text}]}>Your Profile</Text><Text style={[styles.profileSub,{color:muted}]}>Available • GG Messenger</Text><Pressable style={styles.profileButton} onPress={()=>Alert.alert('Profile','Profile editing is ready to connect to Supabase.') }><Text style={styles.profileButtonText}>Edit profile</Text></Pressable></View>}
      <View style={[styles.tabbar,{backgroundColor:card}]}>{[['Chats','▤'],['Status','◉'],['Calls','☎'],['Profile','●']].map(([name,icon])=><Pressable key={name} onPress={()=>setTab(name)} style={styles.tabItem}><Text style={[styles.tabIcon,{color:tab===name?'#2563eb':muted}]}>{icon}</Text><Text style={[styles.tabText,{color:tab===name?'#2563eb':muted,fontWeight:tab===name?'800':'600'}]}>{name}</Text></Pressable>)}</View>
    </SafeAreaView>
  );
}

function EmptyTab({icon,title,text}:{icon:string;title:string;text:string}) { return <View style={styles.emptyTab}><View style={styles.emptyCircle}><Text style={styles.emptyTabIcon}>{icon}</Text></View><Text style={styles.emptyTabTitle}>{title}</Text><Text style={styles.emptyTabText}>{text}</Text></View>; }

const styles=StyleSheet.create({safe:{flex:1},flex:{flex:1},top:{paddingHorizontal:20,paddingTop:14,paddingBottom:12,flexDirection:'row',justifyContent:'space-between',alignItems:'center'},brand:{fontSize:32,fontWeight:'900',letterSpacing:-1},subtitle:{fontSize:12,fontWeight:'600',marginTop:-2},topActions:{flexDirection:'row',gap:10},circle:{width:42,height:42,borderRadius:21,alignItems:'center',justifyContent:'center',backgroundColor:'#eef1f5'},circleText:{fontSize:22},hero:{paddingHorizontal:20,paddingVertical:17},greeting:{fontSize:13,fontWeight:'700'},heroTitle:{fontSize:25,fontWeight:'900',marginTop:3},heroSub:{fontSize:13,marginTop:4,maxWidth:330},searchWrap:{marginHorizontal:16,marginTop:14,marginBottom:12,borderRadius:16,backgroundColor:'#eef1f5',flexDirection:'row',alignItems:'center',paddingHorizontal:14},searchIcon:{fontSize:24,color:'#667085'},search:{flex:1,fontSize:15,paddingVertical:12},sectionRow:{paddingHorizontal:20,flexDirection:'row',justifyContent:'space-between',alignItems:'center',marginBottom:8},sectionTitle:{fontSize:18,fontWeight:'800'},seeAll:{fontSize:13,color:'#2563eb',fontWeight:'700'},list:{paddingHorizontal:12,paddingBottom:90},chat:{padding:13,marginBottom:7,borderRadius:18,flexDirection:'row',alignItems:'center'},avatar:{width:52,height:52,borderRadius:26,backgroundColor:'#172033',alignItems:'center',justifyContent:'center',position:'relative'},avatarLarge:{width:48,height:48,borderRadius:24,backgroundColor:'#172033',alignItems:'center',justifyContent:'center',position:'relative'},avatarText:{color:'#fff',fontWeight:'900',fontSize:19},onlineDot:{position:'absolute',right:0,bottom:1,width:13,height:13,borderRadius:7,backgroundColor:'#22c55e',borderWidth:2,borderColor:'#fff'},chatBody:{flex:1,marginLeft:13},chatNameRow:{flexDirection:'row',justifyContent:'space-between',alignItems:'center'},chatName:{fontSize:16,fontWeight:'800'},time:{fontSize:11},chatPreviewRow:{flexDirection:'row',alignItems:'center',marginTop:5},chatMessage:{fontSize:13,flex:1},badge:{minWidth:21,height:21,borderRadius:11,backgroundColor:'#2563eb',alignItems:'center',justifyContent:'center',marginLeft:8},badgeText:{color:'#fff',fontSize:11,fontWeight:'800'},chatHeader:{height:70,paddingHorizontal:10,flexDirection:'row',alignItems:'center',borderBottomWidth:1,borderBottomColor:'#eceff3'},iconButton:{width:42,height:42,alignItems:'center',justifyContent:'center'},icon:{fontSize:38,lineHeight:40},profileRow:{flex:1,flexDirection:'row',alignItems:'center',gap:10},title:{fontSize:16,fontWeight:'800'},headerActions:{flexDirection:'row',gap:16,paddingRight:10},actionIcon:{fontSize:20,color:'#2563eb'},messages:{flex:1},messageContent:{padding:16,paddingBottom:24},messageLine:{alignItems:'flex-end',marginBottom:8},bubble:{maxWidth:'82%',paddingHorizontal:14,paddingVertical:10,borderRadius:18,borderBottomRightRadius:5},bubbleText:{color:'#fff',fontSize:15,lineHeight:21},read:{color:'#93c5fd',fontSize:10,textAlign:'right',marginTop:2},emptyBox:{alignItems:'center',marginTop:80,paddingHorizontal:30},emptyEmoji:{fontSize:40},emptyTitle:{fontSize:18,fontWeight:'800',marginTop:8},empty:{textAlign:'center',marginTop:5,fontSize:13},composer:{flexDirection:'row',alignItems:'center',padding:10,gap:7,borderTopWidth:1,borderTopColor:'#e5e7eb'},plus:{width:40,height:40,borderRadius:20,alignItems:'center',justifyContent:'center'},plusText:{fontSize:28,color:'#2563eb'},input:{flex:1,borderRadius:22,paddingHorizontal:16,paddingVertical:10,fontSize:15},send:{width:44,height:44,borderRadius:22,backgroundColor:'#2563eb',alignItems:'center',justifyContent:'center'},sendText:{color:'#fff',fontSize:19,fontWeight:'800'},tabbar:{position:'absolute',left:0,right:0,bottom:0,height:70,borderTopWidth:1,borderTopColor:'#e5e7eb',flexDirection:'row',justifyContent:'space-around',alignItems:'center'},tabItem:{alignItems:'center',justifyContent:'center',minWidth:70},tabIcon:{fontSize:19},tabText:{fontSize:11,marginTop:3},emptyTab:{alignItems:'center',justifyContent:'center',flex:1,paddingBottom:70},emptyCircle:{width:74,height:74,borderRadius:37,backgroundColor:'#eaf0ff',alignItems:'center',justifyContent:'center'},emptyTabIcon:{fontSize:30,color:'#2563eb'},emptyTabTitle:{fontSize:21,fontWeight:'900',marginTop:16,color:'#111827'},emptyTabText:{fontSize:14,color:'#6b7280',textAlign:'center',marginTop:6,maxWidth:280},profileCard:{margin:16,borderRadius:22,padding:25,alignItems:'center'},profileAvatar:{width:90,height:90,borderRadius:45,backgroundColor:'#172033',alignItems:'center',justifyContent:'center'},profileInitial:{fontSize:34,color:'#fff',fontWeight:'900'},profileName:{fontSize:22,fontWeight:'900',marginTop:14},profileSub:{fontSize:13,marginTop:4},profileButton:{marginTop:20,borderRadius:14,backgroundColor:'#2563eb',paddingHorizontal:24,paddingVertical:12},profileButtonText:{color:'#fff',fontWeight:'800'}});