import {supabase} from './supabase';

export type Message={id:string;conversation_id:string;sender_id:string;body:string;created_at:string;delivered_at?:string|null;read_at?:string|null};

export async function loadMessages(conversationId:string){const {data,error}=await supabase.from('messages').select('*').eq('conversation_id',conversationId).order('created_at',{ascending:true});if(error)throw error;return(data??[]) as Message[];}

export async function sendMessage(conversationId:string,body:string){const {data:{user}}=await supabase.auth.getUser();if(!user)throw new Error('You must be signed in');const {data,error}=await supabase.from('messages').insert({conversation_id:conversationId,sender_id:user.id,body,delivered_at:new Date().toISOString()}).select().single();if(error)throw error;return data as Message;}

export async function markMessagesRead(conversationId:string){const {data:{user}}=await supabase.auth.getUser();if(!user)return;const {error}=await supabase.from('messages').update({read_at:new Date().toISOString()}).eq('conversation_id',conversationId).neq('sender_id',user.id).is('read_at',null);if(error)throw error;}

export function subscribeToMessages(conversationId:string,onMessage:(message:Message)=>void,onUpdate?:(message:Message)=>void){return supabase.channel(`messages:${conversationId}`).on('postgres_changes',{event:'INSERT',schema:'public',table:'messages',filter:`conversation_id=eq.${conversationId}`},p=>onMessage(p.new as Message)).on('postgres_changes',{event:'UPDATE',schema:'public',table:'messages',filter:`conversation_id=eq.${conversationId}`},p=>onUpdate?.(p.new as Message)).subscribe();}

export function createTypingChannel(conversationId:string,onTyping:(typing:boolean)=>void){const channel=supabase.channel(`typing:${conversationId}`,{config:{broadcast:{self:false}}});channel.on('broadcast',{event:'typing'},({payload})=>onTyping(Boolean(payload?.typing))).subscribe();return channel;}

export async function setTyping(channel:any,typing:boolean){await channel.send({type:'broadcast',event:'typing',payload:{typing}});}
