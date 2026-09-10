import {supabase} from './supabase';

export type Conversation = {id:string;name:string;message:string;time:string;online?:boolean;unread?:number};

export async function loadConversations():Promise<Conversation[]> {
  const {data:{user},error:userError}=await supabase.auth.getUser();
  if(userError) throw userError;
  if(!user) return [];
  const {data:members,error:memberError}=await supabase.from('conversation_members').select('conversation_id').eq('user_id',user.id);
  if(memberError) throw memberError;
  const ids=(members??[]).map(x=>x.conversation_id);
  if(!ids.length)return [];
  const {data:convos,error:conversationError}=await supabase.from('conversations').select('id,title,is_group,created_at').in('id',ids).order('created_at',{ascending:false});
  if(conversationError)throw conversationError;
  const result:Conversation[]=[];
  for(const c of convos??[]){
    const {data:others}=await supabase.from('conversation_members').select('user_id').eq('conversation_id',c.id).neq('user_id',user.id).limit(1);
    const otherId=others?.[0]?.user_id;
    let profile:any=null;
    if(otherId){profile=(await supabase.from('profiles').select('display_name,last_seen').eq('id',otherId).maybeSingle()).data;}
    const last=(await supabase.from('messages').select('body,created_at').eq('conversation_id',c.id).order('created_at',{ascending:false}).limit(1).maybeSingle()).data;
    result.push({id:c.id,name:c.is_group?(c.title||'Group'):(profile?.display_name||'GG User'),message:last?.body||'No messages yet',time:last?.created_at?new Date(last.created_at).toLocaleTimeString([],{hour:'2-digit',minute:'2-digit'}):'',online:!!profile?.last_seen&&Date.now()-new Date(profile.last_seen).getTime()<120000});
  }
  return result;
}

export async function ensureProfile(displayName:string){
  const {data:{user}}=await supabase.auth.getUser();
  if(!user)return;
  await supabase.from('profiles').upsert({id:user.id,display_name:displayName},{onConflict:'id'});
}

export async function searchUsers(query:string){
  const {data:{user}}=await supabase.auth.getUser();
  if(!user)return [];
  const {data,error}=await supabase.from('profiles').select('id,display_name,username,last_seen').neq('id',user.id).ilike('display_name',`%${query.trim()}%`).limit(20);
  if(error)throw error;
  return data??[];
}

export async function createDirectConversation(otherUserId:string){
  const {data:{user},error}=await supabase.auth.getUser();
  if(error)throw error;if(!user)throw new Error('You must be signed in');
  const {data:mine}=await supabase.from('conversation_members').select('conversation_id').eq('user_id',user.id);
  for(const row of mine??[]){
    const {data:other}=await supabase.from('conversation_members').select('user_id').eq('conversation_id',row.conversation_id).eq('user_id',otherUserId).maybeSingle();
    if(other){const {data:c}=await supabase.from('conversations').select('id').eq('id',row.conversation_id).eq('is_group',false).maybeSingle();if(c)return c.id;}
  }
  const {data:c,error:cError}=await supabase.from('conversations').insert({is_group:false}).select('id').single();
  if(cError)throw cError;
  const {error:mError}=await supabase.from('conversation_members').insert([{conversation_id:c.id,user_id:user.id},{conversation_id:c.id,user_id:otherUserId}]);
  if(mError)throw mError;
  return c.id as string;
}
