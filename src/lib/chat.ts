import {supabase} from './supabase';
import AsyncStorage from '@react-native-async-storage/async-storage';

export type Message={id:string;conversation_id:string;sender_id:string;body:string;created_at:string;delivered_at?:string|null;read_at?:string|null;message_type?:'text'|'image'|'video'|'file'|'voice';media_url?:string|null;file_name?:string|null;pending?:boolean};

const CACHE_PREFIX='gg:offline:messages:';
const QUEUE_PREFIX='gg:offline:queue:';

async function getCachedMessages(conversationId:string):Promise<Message[]>{try{const raw=await AsyncStorage.getItem(CACHE_PREFIX+conversationId);return raw?JSON.parse(raw):[]}catch{return[]}}
async function saveCachedMessages(conversationId:string,data:Message[]){try{await AsyncStorage.setItem(CACHE_PREFIX+conversationId,JSON.stringify(data))}catch{}}
async function getQueue(conversationId:string):Promise<Message[]>{try{const raw=await AsyncStorage.getItem(QUEUE_PREFIX+conversationId);return raw?JSON.parse(raw):[]}catch{return[]}}
async function saveQueue(conversationId:string,data:Message[]){try{await AsyncStorage.setItem(QUEUE_PREFIX+conversationId,JSON.stringify(data))}catch{}}

function localId(){return `offline-${Date.now()}-${Math.random().toString(36).slice(2)}`}

export async function loadMessages(conversationId:string){
 const cached=await getCachedMessages(conversationId);
 try{const {data,error}=await supabase.from('messages').select('*').eq('conversation_id',conversationId).order('created_at',{ascending:true});if(error)throw error;const fresh=(data??[]) as Message[];await saveCachedMessages(conversationId,fresh);return [...fresh,...(await getQueue(conversationId)).filter(q=>!fresh.some(m=>m.id===q.id))].sort((a,b)=>a.created_at.localeCompare(b.created_at));}catch(error){if(cached.length)return [...cached,...(await getQueue(conversationId)).filter(q=>!cached.some(m=>m.id===q.id))];throw error;}
}

async function onlineSend(conversationId:string,body:string){const {data,error}=await supabase.from('messages').insert({conversation_id:conversationId,sender_id:(await supabase.auth.getUser()).data.user?.id,body,message_type:'text',media_url:null,file_name:null,delivered_at:new Date().toISOString()}).select().single();if(error)throw error;return data as Message}

export async function flushOfflineMessages(conversationId?:string){
 const ids=conversationId?[conversationId]:await getQueueConversationIds();
 for(const id of ids){const queue=await getQueue(id);if(!queue.length)continue;const remaining:Message[]=[];for(const pending of queue){try{const sent=await onlineSend(id,pending.body);const cached=await getCachedMessages(id);await saveCachedMessages(id,[...cached.filter(x=>x.id!==pending.id&&x.id!==sent.id),sent].sort((a,b)=>a.created_at.localeCompare(b.created_at)));}catch{remaining.push(pending)}}await saveQueue(id,remaining)}
}

async function getQueueConversationIds(){const keys=await AsyncStorage.getAllKeys();return keys.filter(k=>k.startsWith(QUEUE_PREFIX)).map(k=>k.slice(QUEUE_PREFIX.length))}

export async function sendMessage(conversationId:string,body:string){
 const {data:{user}}=await supabase.auth.getUser();if(!user)throw new Error('You must be signed in');
 try{return await onlineSend(conversationId,body)}catch(error){
  const pending:Message={id:localId(),conversation_id:conversationId,sender_id:user.id,body,created_at:new Date().toISOString(),delivered_at:null,read_at:null,message_type:'text',media_url:null,file_name:null,pending:true};
  const queue=await getQueue(conversationId);await saveQueue(conversationId,[...queue,pending]);const cached=await getCachedMessages(conversationId);await saveCachedMessages(conversationId,[...cached,pending]);return pending;
 }
}

export async function sendMediaMessage(conversationId:string,mediaUrl:string,type:'text'|'image'|'video'|'file'|'voice',fileName?:string){const {data:{user},error:u}=await supabase.auth.getUser();if(u)throw u;if(!user)throw new Error('You must be signed in');const {data,error}=await supabase.from('messages').insert({conversation_id:conversationId,sender_id:user.id,body:fileName||type,message_type:type,media_url:type==='text'?null:mediaUrl,file_name:fileName||null,delivered_at:new Date().toISOString()}).select().single();if(error)throw error;const message=data as Message;const cached=await getCachedMessages(conversationId);await saveCachedMessages(conversationId,[...cached.filter(x=>x.id!==message.id),message].sort((a,b)=>a.created_at.localeCompare(b.created_at)));return message;}

export async function markMessagesRead(conversationId:string){const {data:{user}}=await supabase.auth.getUser();if(!user)return;const {error}=await supabase.from('messages').update({read_at:new Date().toISOString()}).eq('conversation_id',conversationId).neq('sender_id',user.id).is('read_at',null);if(error)throw error;}

export function subscribeToMessages(conversationId:string,onMessage:(message:Message)=>void,onUpdate?:(message:Message)=>void){return supabase.channel(`messages:${conversationId}`).on('postgres_changes',{event:'INSERT',schema:'public',table:'messages',filter:`conversation_id=eq.${conversationId}`},p=>{const m=p.new as Message;getCachedMessages(conversationId).then(c=>saveCachedMessages(conversationId,[...c.filter(x=>x.id!==m.id),m].sort((a,b)=>a.created_at.localeCompare(b.created_at))));onMessage(m)}).on('postgres_changes',{event:'UPDATE',schema:'public',table:'messages',filter:`conversation_id=eq.${conversationId}`},p=>{const m=p.new as Message;getCachedMessages(conversationId).then(c=>saveCachedMessages(conversationId,c.map(x=>x.id===m.id?m:x)));onUpdate?.(m)}).subscribe();}

export function createTypingChannel(conversationId:string,onTyping:(typing:boolean)=>void){const channel=supabase.channel(`typing:${conversationId}`,{config:{broadcast:{self:false}}});channel.on('broadcast',{event:'typing'},({payload})=>onTyping(Boolean(payload?.typing))).subscribe();return channel;}
export async function setTyping(channel:any,typing:boolean){await channel.send({type:'broadcast',event:'typing',payload:{typing}});}
