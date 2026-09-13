import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const { prompt, ratio = '16:9', duration = 5, resolution = '1080p', audio_url } = await req.json();
    if (!prompt?.trim()) throw new Error('Prompt is required.');
    const key = Deno.env.get('KIE_API_KEY');
    if (!key) throw new Error('KIE_API_KEY is not configured in Supabase.');

    const input: Record<string, unknown> = {
      prompt,
      negative_prompt: 'blurry, low quality, flicker, distorted characters',
      resolution,
      ratio,
      duration,
      prompt_extend: true,
      watermark: false,
    };
    if (audio_url) input.audio_url = audio_url;

    const r = await fetch('https://api.kie.ai/api/v1/jobs/createTask', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ model: 'wan/2-7-text-to-video', input }),
    });
    const body = await r.text();
    return new Response(body, { status: r.status, headers: { ...cors, 'Content-Type': 'application/json' } });
  } catch (e) {
    return new Response(JSON.stringify({ error: e instanceof Error ? e.message : String(e) }), {
      status: 500, headers: { ...cors, 'Content-Type': 'application/json' },
    });
  }
});
