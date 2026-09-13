import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};
const json = (x: any, status = 200) =>
  new Response(JSON.stringify(x), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });

async function kie(path: string, body?: any, method = 'POST') {
  const key = Deno.env.get('KIE_API_KEY');
  if (!key) throw new Error('KIE_API_KEY is not configured');
  const r = await fetch(`https://api.kie.ai${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${key}`,
      'Content-Type': 'application/json',
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const d = await r.json();
  if (!r.ok || (d.code && d.code !== 200)) {
    throw new Error(d.msg || `KIE request failed (${r.status})`);
  }
  return d;
}

async function groqModels() {
  const key = Deno.env.get('GROQ_API_KEY');
  if (!key) return [];
  try {
    const r = await fetch('https://api.groq.com/openai/v1/models', {
      headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    });
    if (!r.ok) return [];
    const d = await r.json();
    return (d.data || [])
      .filter((x: any) => x.id && !/whisper|guard|tts|speech|transcription/i.test(x.id))
      .map((x: any) => ({
        id: x.id,
        name: x.id,
        speed: /20b|8b|instant/i.test(x.id) ? 'Fast' : /120b|qwen|compound|minimax/i.test(x.id) ? 'Expert' : 'Fast',
        provider: 'Groq',
      }));
  } catch {
    return [];
  }
}

// Supported KIE models. The first Fast model in image/video is the free-tier
// default used by the app. KIE still charges the developer account; "Free"
// here means the app's free user tier, not a free KIE API call.
const MODELS = {
  image: [
    { id: 'seedream/5.0-lite', name: 'Seedream 5 Lite', speed: 'Fast', tier: 'free', provider: 'KIE' },
    { id: 'google/imagen4-fast', name: 'Imagen 4 Fast', speed: 'Fast', tier: 'free', provider: 'KIE' },
    { id: 'google/nano-banana-2', name: 'Nano Banana 2', speed: 'Fast', tier: 'premium', provider: 'KIE' },
    { id: 'seedream/5.0-pro', name: 'Seedream 5 Pro', speed: 'Expert', tier: 'premium', provider: 'KIE' },
    { id: 'google/imagen4', name: 'Imagen 4', speed: 'Quality', tier: 'premium', provider: 'KIE' },
    { id: 'google/nano-banana-pro', name: 'Nano Banana Pro', speed: 'Expert', tier: 'premium', provider: 'KIE' },
    { id: 'flux-2/pro-text-to-image', name: 'Flux 2 Pro', speed: 'Quality', tier: 'premium', provider: 'KIE' },
    { id: 'grok-imagine/text-to-image', name: 'Grok Imagine', speed: 'Fast', tier: 'premium', provider: 'KIE' },
    { id: 'gpt-image-2', name: 'GPT Image 2', speed: 'Quality', tier: 'premium', provider: 'KIE' },
  ],
  video: [
    { id: 'wan/2-2-a14b-text-to-video-turbo', name: 'Wan 2.2 A14B Turbo', speed: 'Fast', tier: 'free', provider: 'KIE' },
    { id: 'pixverse/v6-text-to-video', name: 'PixVerse V6', speed: 'Fast', tier: 'premium', provider: 'KIE' },
    { id: 'kling-3.0-omni/text-to-video', name: 'Kling 3.0 Omni', speed: 'Expert', tier: 'premium', provider: 'KIE' },
    { id: 'wan/2-7-text-to-video', name: 'Wan 2.7', speed: 'Fast', tier: 'premium', provider: 'KIE' },
  ],
  music: [
    { id: 'V6', name: 'Suno V6', speed: 'Expert', tier: 'premium', provider: 'KIE' },
    { id: 'V6_MINI', name: 'Suno V6 Mini', speed: 'Fast', tier: 'free', provider: 'KIE' },
    { id: 'V5_5', name: 'Suno V5.5', speed: 'Quality', tier: 'premium', provider: 'KIE' },
    { id: 'V5', name: 'Suno V5', speed: 'Fast', tier: 'premium', provider: 'KIE' },
    { id: 'V4_5ALL', name: 'Suno V4.5 All', speed: 'Fast', tier: 'premium', provider: 'KIE' },
    { id: 'V4_5PLUS', name: 'Suno V4.5 Plus', speed: 'Quality', tier: 'premium', provider: 'KIE' },
  ],
};

const FREE_MODELS: Record<string, string> = {
  image: 'seedream/5.0-lite',
  video: 'wan/2-2-a14b-text-to-video-turbo',
  music: 'V6_MINI',
};

function normalizeRequestedModel(type: string, requested: string | undefined, freeMode = false) {
  const list = (MODELS as any)[type] || [];
  const free = FREE_MODELS[type];
  if (freeMode) return free || list[0]?.id;
  if (!requested || requested === 'auto') return list[0]?.id;
  const found = list.find((x: any) => x.id === requested);
  if (found) return found.id;

  // Older app builds sent aliases that KIE does not accept. Keep those builds
  // working by routing unknown/retired free selections to the supported free model.
  if (type === 'video' && /kling\/v3-turbo|veo3|runway/i.test(requested)) return FREE_MODELS.video;
  if (type === 'image' && /gpt-image-2|nano-banana|seedream/i.test(requested)) return requested;
  return free || list[0]?.id;
}

function choose(type: string, mode: string, chat: any[] = []) {
  if (type === 'chat') {
    if (mode === 'expert') return chat.find((x: any) => x.id === 'openai/gpt-oss-120b')?.id || 'openai/gpt-oss-120b';
    if (mode === 'fast') return chat.find((x: any) => x.id === 'openai/gpt-oss-20b')?.id || 'openai/gpt-oss-20b';
    return mode === 'auto' ? 'openai/gpt-oss-20b' : mode;
  }
  const list = (MODELS as any)[type] || [];
  if (mode === 'expert') return list.find((x: any) => x.speed === 'Expert' || x.speed === 'Quality')?.id || list[0]?.id;
  if (mode === 'fast') return list.find((x: any) => x.speed === 'Fast' && x.tier === 'free')?.id || FREE_MODELS[type] || list[0]?.id;
  if (mode === 'auto') return FREE_MODELS[type] || list[0]?.id;
  return normalizeRequestedModel(type, mode, false);
}

function normalize(type: string, d: any) {
  const data = d?.data || {};
  if (type === 'video') {
    return {
      status: data.state || 'pending',
      url: data.videoInfo?.videoUrl,
      urls: data.videoInfo?.videoUrl ? [data.videoInfo.videoUrl] : [],
      raw: d,
    };
  }
  if (type === 'music') {
    const tracks = data.response?.sunoData || [];
    const urls = tracks.map((x: any) => x.audio_url).filter(Boolean);
    return { status: data.status || 'pending', url: urls[0], urls, raw: d };
  }
  const result = typeof data.resultJson === 'string'
    ? (() => { try { return JSON.parse(data.resultJson); } catch { return {}; } })()
    : data.resultJson || {};
  const urls = result.resultUrls || result.result_urls || result.urls || [];
  return { status: data.state || 'pending', url: urls[0], urls, raw: d };
}

serve(async req => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const body = await req.json();
    const { type, prompt, options = {}, action = 'generate', taskId } = body;
    const chat = action === 'models' ? await groqModels() : [];

    if (action === 'models') {
      return json({
        models: MODELS,
        freeModels: FREE_MODELS,
        chat,
        presets: [
          { id: 'auto', name: 'Free / Auto', speed: 'Free supported model' },
          { id: 'fast', name: 'Fast', speed: 'Free supported model' },
          { id: 'expert', name: 'Expert', speed: 'Premium quality' },
        ],
      });
    }

    const auth = req.headers.get('Authorization');
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const service = serviceKey
      ? createClient(Deno.env.get('SUPABASE_URL')!, serviceKey, { global: { headers: auth ? { Authorization: auth } : {} } })
      : null;
    let userId: string | null = null;
    if (service && auth) {
      const { data: { user } } = await service.auth.getUser();
      userId = user?.id || null;
    }

    if (action === 'status') {
      if (!taskId) return json({ error: 'taskId is required' }, 400);
      const d = await kie(`/api/v1/jobs/recordInfo?taskId=${encodeURIComponent(taskId)}`, undefined, 'GET');
      return json(normalize(type, d));
    }

    if (!prompt?.trim()) return json({ error: 'Prompt is required' }, 400);
    const callbackUrl = `${Deno.env.get('SUPABASE_URL')}/functions/v1/ai-callback`;
    const freeMode = options.freeMode === true || options.plan === 'free';

    if (type === 'image') {
      const model = normalizeRequestedModel('image', options.model, freeMode);
      const d = await kie('/api/v1/jobs/createTask', {
        model,
        callBackUrl: callbackUrl,
        input: {
          prompt,
          aspect_ratio: options.aspectRatio || '1:1',
          resolution: options.resolution || '1K',
          nsfw_checker: true,
        },
      });
      const id = d.data?.taskId;
      if (service && userId && id) await service.from('ai_generations').insert({ user_id: userId, type: 'image', prompt, model, task_id: id, status: 'pending' });
      return json({ taskId: id, status: 'pending', model, tier: freeMode ? 'free' : 'premium', raw: d });
    }

    if (type === 'video') {
      const model = freeMode
        ? FREE_MODELS.video
        : normalizeRequestedModel('video', options.model, false);
      const input: any = {
        prompt,
        resolution: options.quality === '1080p' ? '1080p' : '720p',
        aspect_ratio: options.aspectRatio || '16:9',
        enable_prompt_expansion: false,
        acceleration: 'none',
        nsfw_checker: true,
      };
      if (model === FREE_MODELS.video) {
        input.duration = Math.min(10, Math.max(5, Number(options.duration || 5)));
      } else if (model === 'kling-3.0-omni/text-to-video') {
        input.audio = options.generateAudio ?? false;
        input.duration = Math.min(15, Math.max(3, Number(options.duration || 5)));
        input.customize_multi_shots = false;
      } else if (model === 'pixverse/v6-text-to-video') {
        input.duration = Math.min(8, Math.max(5, Number(options.duration || 5)));
        input.generate_audio_switch = options.generateAudio ?? false;
      } else if (model === 'wan/2-7-text-to-video') {
        input.duration = Math.min(10, Math.max(5, Number(options.duration || 5)));
        input.prompt_extend = true;
        input.watermark = false;
      }
      const d = await kie('/api/v1/jobs/createTask', { model, callBackUrl: callbackUrl, input });
      const id = d.data?.taskId;
      if (service && userId && id) await service.from('ai_generations').insert({ user_id: userId, type: 'video', prompt, model, task_id: id, status: 'pending' });
      return json({ taskId: id, status: 'pending', model, tier: freeMode ? 'free' : 'premium', raw: d });
    }

    if (type === 'music') {
      const model = normalizeRequestedModel('music', options.model, freeMode);
      const d = await kie('/api/v1/generate', {
        prompt,
        customMode: false,
        instrumental: options.instrumental ?? false,
        model,
        callBackUrl: callbackUrl,
      });
      const id = d.data?.taskId;
      if (service && userId && id) await service.from('ai_generations').insert({ user_id: userId, type: 'music', prompt, model, task_id: id, status: 'pending' });
      return json({ taskId: id, status: 'PENDING', model, tier: freeMode ? 'free' : 'premium', raw: d });
    }

    const groq = Deno.env.get('GROQ_API_KEY');
    if (!groq) throw new Error('GROQ_API_KEY is not configured');
    const model = choose('chat', options.model || 'auto', await groqModels());
    const r = await fetch('https://api.groq.com/openai/v1/chat/completions', {
      method: 'POST',
      headers: { Authorization: `Bearer ${groq}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model,
        messages: [
          { role: 'system', content: 'You are GG AI, a fast, helpful and premium AI assistant inside GG Messenger. Give accurate, useful and well-structured answers.' },
          { role: 'user', content: prompt },
        ],
        temperature: 0.7,
      }),
    });
    const d = await r.json();
    if (!r.ok) throw new Error(d.error?.message || 'Groq AI request failed');
    return json({ message: d.choices?.[0]?.message?.content || '', status: 'success', model: d.model || model, raw: d });
  } catch (e) {
    return json({ error: e instanceof Error ? e.message : 'AI generation failed' }, 500);
  }
});
