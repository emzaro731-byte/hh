import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const { prompt, size = '1:1', nVariants = 1, isEnhance = false } = await req.json();
    if (!prompt?.trim()) throw new Error('Prompt is required.');
    const key = Deno.env.get('KIE_API_KEY');
    if (!key) throw new Error('KIE_API_KEY is not configured in Supabase.');

    const r = await fetch('https://api.kie.ai/api/v1/gpt4o-image/generate', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ prompt, size, nVariants, isEnhance }),
    });
    const body = await r.text();
    return new Response(body, { status: r.status, headers: { ...cors, 'Content-Type': 'application/json' } });
  } catch (e) {
    return new Response(JSON.stringify({ error: e instanceof Error ? e.message : String(e) }), {
      status: 500, headers: { ...cors, 'Content-Type': 'application/json' },
    });
  }
});
