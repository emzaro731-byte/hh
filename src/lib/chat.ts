import {supabase} from './supabase';
import AsyncStorage from '@react-native-async-storage/async-storage';

export type Message={id:string;conversation_id:string;sender_id:string;body:string;created_at:string;delivered_at?:string|null;read_at?:string|null;message_type?:'text'|'image'|'video'|'file'|'voice';media_url?:string|null;file_name?:string|null};

const CACHE_PREFIX='gg:offline:messages:';
async function getCachedMessages(conversationId:string):Promise<Message[]>{try{const raw=await AsyncStorage.getItem(CACHE_PREFIX+conversationId);return raw?JSON.parse(raw):[]}catch{return[]}}
async function saveCachedMessages(conversationId:string,data:Message[]){try{await AsyncStorage.setItem(CACHE_PREFIX+conversationId,JSON.stringify(data))}catch{}}

export async function loadMessages(conversationId:string){
 const cached=await getCachedMessages(conversationId);
 try{const {data,error}=await supabase.from('messages').select('*').eq('conversation_id',conversationId).order('created_at',{ascending:true});if(error)throw error;const fresh=(data??[]) as Message[];await saveCachedMessages(conversationId,fresh);return fresh.length?fresh:cached}catch(error){if(cached.length)return cached;throw error;}
}

export async function sendMessage(conversationId:string,body:string){return sendMediaMessage(conversationId,body,'text');}

export async function sendMediaMessage(conversationId:string,mediaUrl:string,type:'text'|'image'|'video'|'file'|'voice',fileName?:string){const {data:{user},error:u}=await supabase.auth.getUser();if(u)throw u;if(!user)throw new Error('You must be signed in');const {data,error}=await supabase.from('messages').insert({conversation_id:conversationId,sender_id:user.id,body:fileName||type,message_type:type,media_url:type==='text'?null:mediaUrl,file_name:fileName||null,delivered_at:new Date().toISOString()}).select().single();if(error)throw error;const message=data as Message;const cached=await getCachedMessages(conversationId);await saveCachedMessages(conversationId,[...cached.filter(x=>x.id!==message.id),message].sort((a,b)=>a.created_at.localeCompare(b.created_at)));return message;}

export async function markMessagesRead(conversationId:string){const {data:{user}}=await supabase.auth.getUser();if(!user)return;const {error}=await supabase.from('messages').update({read_at:new Date().toISOString()}).eq('conversation_id',conversationId).neq('sender_id',user.id).is('read_at',null);if(error)throw error;}

export function subscribeToMessages(conversationId:string,onMessage:(message:Message)=>void,onUpdate?:(message:Message)=>void){return supabase.channel(`messages:${conversationId}`).on('postgres_changes',{event:'INSERT',schema:'public',table:'messages',filter:`conversation_id=eq.${conversationId}`},p=>{const m=p.new as Message;getCachedMessages(conversationId).then(c=>saveCachedMessages(conversationId,[...c.filter(x=>x.id!==m.id),m].sort((a,b)=>a.created_at.localeCompare(b.created_at))));onMessage(m)}).on('postgres_changes',{event:'UPDATE',schema:'public',table:'messages',filter:`conversation_id=eq.${conversationId}`},p=>{const m=p.new as Message;getCachedMessages(conversationId).then(c=>saveCachedMessages(conversationId,c.map(x=>x.id===m.id?m:x)));onUpdate?.(m)}).subscribe();}

export function createTypingChannel(conversationId:string,onTyping:(typing:boolean)=>void){const channel=supabase.channel(`typing:${conversationId}`,{config:{broadcast:{self:false}}});channel.on('broadcast',{event:'typing'},({payload})=>onTyping(Boolean(payload?.typing))).subscribe();return channel;}
export async function setTyping(channel:any,typing:boolean){await channel.send({type:'broadcast',event:'typing',payload:{typing}});}
