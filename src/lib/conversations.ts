import {supabase} from './supabase';

export type Conversation = {id: string; title: string | null; is_group: boolean; created_at: string};

export async function loadMyConversations() {
  const {data: memberships, error: memberError} = await supabase
    .from('conversation_members').select('conversation_id').eq('user_id', (await supabase.auth.getUser()).data.user?.id ?? '');
  if (memberError) throw memberError;
  const ids = (memberships ?? []).map(x => x.conversation_id);
  if (!ids.length) return [] as Conversation[];
  const {data, error} = await supabase.from('conversations').select('*').in('id', ids).order('created_at', {ascending: false});
  if (error) throw error;
  return (data ?? []) as Conversation[];
}

export async function ensureProfile(displayName: string) {
  const {data: {user}} = await supabase.auth.getUser();
  if (!user) return;
  await supabase.from('profiles').upsert({id: user.id, display_name: displayName}, {onConflict: 'id'});
}
