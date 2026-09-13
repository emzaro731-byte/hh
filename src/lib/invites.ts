import {supabase} from './supabase';

const alphabet='ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
function token(){let out='';for(let i=0;i<24;i++)out+=alphabet[Math.floor(Math.random()*alphabet.length)];return out;}

export type Invite={id:string;conversation_id:string;token:string};

export async function createConversationInvite(conversationId:string){
 const {data:{user},error:u}=await supabase.auth.getUser();if(u)throw u;if(!user)throw new Error('Please sign in again');
 const {data:member}=await supabase.from('conversation_members').select('conversation_id').eq('conversation_id',conversationId).eq('user_id',user.id).maybeSingle();
 if(!member)throw new Error('Only members can create an invite');
 const {data,error}=await supabase.from('conversation_invites').insert({conversation_id:conversationId,created_by:user.id,token:token()}).select('id,conversation_id,token').single();
 if(error)throw error;return data as Invite;
}

export async function joinConversationByInvite(inviteToken:string){
 const clean=inviteToken.trim().replace(/^gg:\/\/invite\//,'');if(!clean)throw new Error('Invalid invite');
 const {data:{user},error:u}=await supabase.auth.getUser();if(u)throw u;if(!user)throw new Error('Please sign in first');
 const {data:invite,error}=await supabase.from('conversation_invites').select('id,conversation_id,token').eq('token',clean).maybeSingle();
 if(error)throw error;if(!invite)throw new Error('This invite link is invalid or expired');
 const {error:m}=await supabase.from('conversation_members').upsert({conversation_id:invite.conversation_id,user_id:user.id},{onConflict:'conversation_id,user_id'});
 if(m)throw m;return invite.conversation_id as string;
}

export function inviteLink(t:string){return `gg://invite/${t}`;}
