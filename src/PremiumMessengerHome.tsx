import React,{useEffect,useMemo,useState}from'react';
import{FlatList,Modal,Pressable,SafeAreaView,StatusBar,StyleSheet,Text,TextInput,View}from'react-native';
import{Conversation,loadConversations}from'./lib/conversations';
import MessengerHome from'./MessengerHome';

const BG='#061015',CARD='#0d171c',TEXT='#f4f7f8',MUTED='#8ea0ad',GREEN='#00e676',GREEN_DARK='#063d2a',LINE='#1b2930';
const SAMPLE=[
{name:'Fun and experience',message:'FavTech academy:  ◎  @  This group was me...',time:'Yesterday',badge:'8'},
{name:'Ai smart trader Bot comm...',message:'~ Rider:  ◎  @  This group was me...',time:'Yesterday',badge:'20'},
{name:'Ella',message:'☎ Voice call',time:'Yesterday'},
{name:'Jamb 380 and Above',message:'Jamb, Waec and Postutme 1   ▶   أرجو...',time:''},
{name:'+234 817 239 8083',message:'✓✓ Can u deliver this Wednesday',time:'Yesterday'},
{name:'Baddy E',message:'✓✓ Startimes Rivers Main Office  ...',time:'Yesterday'},
{name:'FINANCIAL FREEDOM 13',message:'~ abrahamstephen587:  ▧  🔥 🔥 ...',time:''}
];
const STATUS=[
{name:'Add status',kind:'add',initials:'+'},
{name:'Samuel',initials:'S',ring:true},
{name:'FavTech academy',initials:'FA',ring:true},
{name:'Bro Tonye',initials:'BT',ring:true},
{name:'Emma',initials:'E',ring:true}
];
const CHANNELS=[
{name:'FABRIZIO ROMANO ⚽',preview:'🎥 🚨 MIDNIGHT CRASH SIGN...',time:'Yesterday',badge:'804',initials:'FR'},
{name:'Vikesh',preview:'▣ Midnight ticket. 🇳🇬  2.21 od...',time:'Yesterday',badge:'127',initials:'10'},
{name:'Job Source Global | Tech...',preview:'🔗 ♻ Remote Full Stack Developer...',time:'Yesterday',initials:'JG'},
{name:'Livescore ❤️☑️',preview:'▣ Let’s see the biggest fans he...',time:'Yesterday',initials:'LS'},
{name:'Electricity Substation Suj...',preview:'▣ Power supply update today...',time:'Yesterday',initials:'33'}
];

export default function PremiumMessengerHome(){
 const[chats,setChats]=useState<Conversation[]>([]),[loading,setLoading]=useState(true),[query,setQuery]=useState(''),[menu,setMenu]=useState(false),[open,setOpen]=useState(false),[tab,setTab]=useState('Updates');
 const refresh=async()=>{setLoading(true);try{setChats(await loadConversations())}catch{}finally{setLoading(false)}};
 useEffect(()=>{refresh()},[]);
 const filtered=useMemo(()=>chats.filter(c=>c.name.toLowerCase().includes(query.toLowerCase())),[chats,query]);
 const data:any[]=filtered.length?filtered:SAMPLE.filter(x=>x.name.toLowerCase().includes(query.toLowerCase()));
 if(open)return <MessengerHome/>;
 const go=(x:string)=>{setTab(x);if(x==='Chats')setOpen(true)};
 return <SafeAreaView style={s.safe}>
  <StatusBar barStyle="light-content" backgroundColor={BG}/>
  <View style={s.header}><Text style={s.title}>GG Messenger</Text><View style={s.headerActions}><Pressable hitSlop={12}><Text style={s.camera}>⌾</Text></Pressable><Pressable onPress={()=>setMenu(true)} hitSlop={12}><Text style={s.more}>⋮</Text></Pressable></View></View>
  <FlatList data={tab==='Chats'?data:CHANNELS} keyExtractor={(x:any,i)=>x.id||`${x.name}-${i}`} refreshing={loading} onRefresh={refresh} contentContainerStyle={s.content}
   ListHeaderComponent={<>
    {tab==='Updates'?<>
      <Text style={s.pageTitle}>Updates</Text><Text style={s.sectionTitle}>Status</Text>
      <FlatList horizontal showsHorizontalScrollIndicator={false} data={STATUS} keyExtractor={x=>x.name} contentContainerStyle={s.statusList} renderItem={({item})=><Pressable style={s.statusCard} onPress={()=>item.kind!=='add'&&setMenu(true)}>
       <View style={[s.statusAvatar,item.ring&&s.statusRing]}><Text style={s.statusInitial}>{item.kind==='add'?'▣':item.initials}</Text>{item.kind==='add'&&<View style={s.plus}><Text style={s.plusText}>+</Text></View>}</View><Text numberOfLines={2} style={s.statusName}>{item.name}</Text>
      </Pressable>}/>
      <View style={s.channelHeader}><Text style={s.sectionTitle}>Channels</Text><Pressable style={s.explore}><Text style={s.exploreText}>Explore</Text></Pressable></View>
    </>:<>
      <View style={s.chatHeader}><Text style={s.pageTitle}>Chats</Text><View style={s.searchMini}><Text style={s.searchIcon}>⌕</Text><TextInput value={query} onChangeText={setQuery} placeholder="Search chats" placeholderTextColor={MUTED} style={s.searchInput}/></View></View>
    </>}
   </>}
   renderItem={({item,index})=>tab==='Updates'?<Pressable style={s.channel} onPress={()=>setMenu(true)}>
      <View style={[s.channelAvatar,index===1?s.ten:index===3?s.orange:s.avatarBase]}><Text style={s.avatarText}>{item.initials}</Text></View><View style={s.channelInfo}><View style={s.channelNameRow}><Text numberOfLines={1} style={s.channelName}>{item.name}</Text><Text style={[s.channelTime,{color:item.badge?GREEN:MUTED}]}>{item.time}</Text></View><View style={s.previewRow}><Text numberOfLines={1} style={s.preview}>{item.preview}</Text>{item.badge&&<View style={s.badge}><Text style={s.badgeText}>{item.badge}</Text></View>}</View></View>
    </Pressable>:<Pressable style={s.chat} onPress={()=>setOpen(true)}><View style={s.chatAvatar}><Text style={s.avatarText}>{item.name.slice(0,2).toUpperCase()}</Text></View><View style={s.chatInfo}><View style={s.row}><Text style={s.name}>{item.name}</Text><Text style={s.time}>{item.time}</Text></View><Text numberOfLines={1} style={s.preview}>{item.message||'No messages yet'}</Text></View></Pressable>}
  />
  {tab==='Updates'&&<><Pressable style={s.editFab}><Text style={s.editText}>✎</Text></Pressable><Pressable style={s.cameraFab}><Text style={s.cameraFabText}>▣+</Text></Pressable></>}
  <View style={s.bottom}>{['Chats','Updates','Communities','Calls'].map((x,i)=><Pressable key={x} style={s.bottomItem} onPress={()=>go(x)}><View style={[s.iconPill,tab===x&&s.iconPillActive]}><Text style={[s.bottomIcon,tab===x&&s.active]}>{i===0?'▰':i===1?'◉':i===2?'♧':'⌕'}</Text>{x==='Chats'&&<View style={s.bottomBadge}><Text style={s.badgeText}>20</Text></View>}</View><Text style={[s.bottomText,tab===x&&s.active]}>{x}</Text></Pressable>)}</View>
  <Modal transparent visible={menu} animationType="fade" onRequestClose={()=>setMenu(false)}><Pressable style={s.modal} onPress={()=>setMenu(false)}><View style={s.menu}><Text style={s.menuTitle}>GG Messenger</Text><Pressable style={s.menuRow} onPress={()=>{setMenu(false);setOpen(true)}}><Text style={s.menuText}>Open chat</Text></Pressable><Pressable style={s.menuRow} onPress={()=>setMenu(false)}><Text style={s.menuText}>Create status</Text></Pressable><Pressable style={s.menuRow} onPress={()=>setMenu(false)}><Text style={s.menuText}>Settings</Text></Pressable></View></Pressable></Modal>
 </SafeAreaView>
}

const s=StyleSheet.create({
 safe:{flex:1,backgroundColor:BG},header:{height:72,paddingHorizontal:24,flexDirection:'row',alignItems:'center',justifyContent:'space-between'},title:{color:TEXT,fontSize:28,fontWeight:'900',letterSpacing:-.8},headerActions:{flexDirection:'row',alignItems:'center',gap:20},camera:{color:TEXT,fontSize:31,fontWeight:'700'},more:{color:TEXT,fontSize:30,fontWeight:'900'},content:{paddingBottom:112},pageTitle:{color:TEXT,fontSize:34,fontWeight:'900',paddingHorizontal:32,paddingTop:10,paddingBottom:12,letterSpacing:-1},sectionTitle:{color:TEXT,fontSize:27,fontWeight:'900',paddingHorizontal:32,paddingTop:4,paddingBottom:14},statusList:{paddingLeft:32,paddingRight:18,gap:14,paddingBottom:24},statusCard:{width:145,height:218,borderRadius:25,backgroundColor:CARD,borderWidth:1,borderColor:'#1e3038',padding:14,justifyContent:'space-between'},statusAvatar:{width:88,height:88,borderRadius:44,alignSelf:'center',alignItems:'center',justifyContent:'center',backgroundColor:'#17242b',borderWidth:3,borderColor:'#31434c',position:'relative'},statusRing:{borderColor:GREEN},statusInitial:{color:TEXT,fontSize:25,fontWeight:'900',textAlign:'center'},plus:{position:'absolute',right:-9,bottom:-2,width:35,height:35,borderRadius:18,backgroundColor:GREEN,alignItems:'center',justifyContent:'center'},plusText:{color:'#001b10',fontSize:25,fontWeight:'900'},statusName:{color:TEXT,fontSize:16,fontWeight:'800',lineHeight:19},channelHeader:{flexDirection:'row',alignItems:'center',justifyContent:'space-between',paddingRight:24},explore:{backgroundColor:'#16252c',borderRadius:28,paddingHorizontal:27,paddingVertical:13},exploreText:{color:TEXT,fontSize:16,fontWeight:'800'},channel:{minHeight:94,paddingHorizontal:32,flexDirection:'row',alignItems:'center'},channelAvatar:{width:68,height:68,borderRadius:34,alignItems:'center',justifyContent:'center',marginRight:18,borderWidth:2,borderColor:'#203039'},avatarBase:{backgroundColor:'#f1f4f5'},ten:{backgroundColor:GREEN},orange:{backgroundColor:'#ff6200'},avatarText:{color:'#0a151a',fontSize:17,fontWeight:'900',textAlign:'center'},channelInfo:{flex:1,minWidth:0},channelNameRow:{flexDirection:'row',alignItems:'center',justifyContent:'space-between},channelName:{color:TEXT,fontSize:17,fontWeight:'900',flex:1,marginRight:8},channelTime:{fontSize:13,fontWeight:'800'},previewRow:{flexDirection:'row',alignItems:'center',marginTop:5},preview:{color:MUTED,fontSize:15,fontWeight:'650',flex:1},badge:{minWidth:35,height:35,paddingHorizontal:8,borderRadius:18,backgroundColor:GREEN,alignItems:'center',justifyContent:'center',marginLeft:8},badgeText:{color:'#001b10',fontSize:13,fontWeight:'900'},editFab:{position:'absolute',right:28,bottom:168,width:55,height:55,borderRadius:18,backgroundColor:'#16242a',alignItems:'center',justifyContent:'center',elevation:7},editText:{color:TEXT,fontSize:27},cameraFab:{position:'absolute',right:22,bottom:98,width:70,height:70,borderRadius:21,backgroundColor:GREEN,alignItems:'center',justifyContent:'center',elevation:10},cameraFabText:{color:'#001b10',fontSize:23,fontWeight:'900'},bottom:{position:'absolute',left:0,right:0,bottom:0,height:88,borderTopWidth:1,borderTopColor:LINE,backgroundColor:BG,flexDirection:'row',alignItems:'center',justifyContent:'space-around'},bottomItem:{alignItems:'center',width:'25%',position:'relative'},iconPill:{height:36,minWidth:64,borderRadius:20,alignItems:'center',justifyContent:'center'},iconPillActive:{backgroundColor:GREEN_DARK},bottomIcon:{color:'#dbe3e7',fontSize:24},active:{color:GREEN},bottomText:{color:'#dbe3e7',fontSize:13,fontWeight:'900',marginTop:4},bottomBadge:{position:'absolute',right:-4,top:-9,minWidth:22,height:22,borderRadius:12,backgroundColor:GREEN,alignItems:'center',justifyContent:'center'},modal:{flex:1,backgroundColor:'rgba(0,0,0,.62)',alignItems:'flex-end',paddingTop:58,paddingRight:14},menu:{width:220,borderRadius:16,backgroundColor:'#172329',paddingVertical:8,elevation:12},menuTitle:{color:TEXT,fontSize:16,fontWeight:'900',paddingHorizontal:16,paddingVertical:10},menuRow:{paddingHorizontal:16,paddingVertical:14},menuText:{color:TEXT,fontSize:15,fontWeight:'700'},chatHeader:{paddingBottom:4},searchMini:{marginHorizontal:24,height:54,borderRadius:28,backgroundColor:'#182229',flexDirection:'row',alignItems:'center',paddingHorizontal:16},searchIcon:{color:MUTED,fontSize:28},searchInput:{flex:1,color:TEXT,fontSize:17,marginLeft:8},chat:{minHeight:88,paddingHorizontal:24,flexDirection:'row',alignItems:'center'},chatAvatar:{width:62,height:62,borderRadius:31,backgroundColor:'#dbe4ff',alignItems:'center',justifyContent:'center',marginRight:16},chatInfo:{flex:1,height:70,justifyContent:'center',borderBottomWidth:1,borderBottomColor:LINE},row:{flexDirection:'row',alignItems:'center',justifyContent:'space-between'},name:{color:TEXT,fontSize:17,fontWeight:'900',flex:1},time:{color:MUTED,fontSize:12,fontWeight:'700'}
});