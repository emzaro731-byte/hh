import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';

const cors = {'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type'};
serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', {headers:cors});
  try {
    const body = await req.json();
    const prompt = typeof body.prompt === 'string' ? body.prompt.trim() : '';
    if (!prompt) throw new Error('A music prompt is required.');
    const url = Deno.env.get('MUSIC_API_URL');
    const key = Deno.env.get('MUSIC_API_KEY');
    if (!url || !key) throw new Error('MUSIC_API_URL and MUSIC_API_KEY are not configured in Supabase.');
    const response = await fetch(url, {
      method:'POST',
      headers:{'Content-Type':'application/json','Authorization':`Bearer ${key}`},
      body:JSON.stringify({prompt, duration:body.duration ?? '30'})
    });
    const text = await response.text();
    return new Response(text, {status:response.status, headers:{...cors,'Content-Type':'application/json'}});
  } catch (error) {
    return new Response(JSON.stringify({error:error instanceof Error ? error.message : String(error)}), {status:500, headers:{...cors,'Content-Type':'application/json'}});
  }
});
