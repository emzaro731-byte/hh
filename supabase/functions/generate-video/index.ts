import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const body = await req.json();
    const prompt = typeof body.prompt === 'string' ? body.prompt.trim() : '';
    if (!prompt) throw new Error('Prompt is required.');

    const key = Deno.env.get('KIE_API_KEY');
    if (!key) throw new Error('KIE_API_KEY is not configured in Supabase.');

    const input: Record<string, unknown> = {
      prompt,
      aspectRatio: body.ratio ?? '16:9',
      duration: Number(body.duration ?? 5),
      quality: body.resolution === '1080p' ? '1080p' : '720p',
      waterMark: '',
    };
    if (typeof body.imageUrl === 'string' && body.imageUrl.trim()) {
      input.imageUrl = body.imageUrl.trim();
    }

    const r = await fetch('https://api.kie.ai/api/v1/jobs/createTask', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${key}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: Deno.env.get('KIE_VIDEO_MODEL') ?? 'runway/generate-ai-video',
        input,
      }),
    });

    const responseBody = await r.text();
    return new Response(responseBody, {
      status: r.status,
      headers: { ...cors, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({
      error: e instanceof Error ? e.message : String(e),
    }), {
      status: 500,
      headers: { ...cors, 'Content-Type': 'application/json' },
    });
  }
});
