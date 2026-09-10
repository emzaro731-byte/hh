import {supabase} from './supabase';

export type Message = {
  id: string;
  conversation_id: string;
  sender_id: string;
  body: string;
  created_at: string;
  read_at?: string | null;
};

export async function loadMessages(conversationId: string) {
  const {data, error} = await supabase
    .from('messages')
    .select('*')
    .eq('conversation_id', conversationId)
    .order('created_at', {ascending: true});
  if (error) throw error;
  return (data ?? []) as Message[];
}

export async function sendMessage(conversationId: string, body: string) {
  const {data: userData} = await supabase.auth.getUser();
  if (!userData.user) throw new Error('You must be signed in');
  const {data, error} = await supabase
    .from('messages')
    .insert({conversation_id: conversationId, sender_id: userData.user.id, body})
    .select()
    .single();
  if (error) throw error;
  return data as Message;
}

export function subscribeToMessages(conversationId: string, onMessage: (message: Message) => void) {
  return supabase
    .channel(`messages:${conversationId}`)
    .on('postgres_changes', {event: 'INSERT', schema: 'public', table: 'messages', filter: `conversation_id=eq.${conversationId}`}, payload => onMessage(payload.new as Message))
    .subscribe();
}
