import {supabase} from './supabase';

export type CallType='audio'|'video';
export type CallRole='caller'|'callee';

export type Call={id:string;caller_id:string;callee_id:string;type:CallType;status:'ringing'|'active'|'ended'|'rejected';created_at:string;ended_at?:string|null};

export async function createCall(calleeId:string,type:CallType){
  const {data:{user}}=await supabase.auth.getUser();
  if(!user)throw new Error('You must be signed in');
  const {data,error}=await supabase.from('calls').insert({caller_id:user.id,callee_id:calleeId,type,status:'ringing'}).select().single();
  if(error)throw error;
  return data as Call;
}

export async function getCall(callId:string){
  const {data,error}=await supabase.from('calls').select('*').eq('id',callId).single();
  if(error)throw error;
  return data as Call;
}

export async function setCallStatus(callId:string,status:Call['status']){
  const patch:any={status};
  if(status==='ended'||status==='rejected')patch.ended_at=new Date().toISOString();
  const {error}=await supabase.from('calls').update(patch).eq('id',callId);
  if(error)throw error;
}

export async function sendCallSignal(callId:string,kind:'offer'|'answer'|'candidate',payload:any){
  const {data:{user}}=await supabase.auth.getUser();
  if(!user)throw new Error('You must be signed in');
  const {error}=await supabase.from('call_signals').insert({call_id:callId,sender_id:user.id,kind,payload});
  if(error)throw error;
}

export async function loadCallSignals(callId:string){
  const {data,error}=await supabase.from('call_signals').select('*').eq('call_id',callId).order('created_at',{ascending:true});
  if(error)throw error;
  return data??[];
}

export function subscribeToCall(callId:string,onCall:(call:Call)=>void,onSignal:(signal:any)=>void){
  const channel=supabase.channel(`call:${callId}`)
    .on('postgres_changes',{event:'UPDATE',schema:'public',table:'calls',filter:`id=eq.${callId}`},p=>onCall(p.new as Call))
    .on('postgres_changes',{event:'INSERT',schema:'public',table:'call_signals',filter:`call_id=eq.${callId}`},p=>onSignal(p.new))
    .subscribe();
  return channel;
}

export function subscribeToIncomingCalls(userId:string,onCall:(call:Call)=>void){
  const channel=supabase.channel(`incoming-calls:${userId}`)
    .on('postgres_changes',{event:'INSERT',schema:'public',table:'calls',filter:`callee_id=eq.${userId}`},p=>onCall(p.new as Call))
    .subscribe();
  return channel;
}
