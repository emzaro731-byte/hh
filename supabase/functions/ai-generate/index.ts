import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type'};
const json = (x:any,status=200) => new Response(JSON.stringify(x), {status, headers:{...cors,'Content-Type':'application/json'}});

async function kie(path:string, body?:any, method='POST') {
  const key = Deno.env.get('KIE_API_KEY');
  if (!key) throw new Error('KIE_API_KEY is not configured');
  const r = await fetch(`https://api.kie.ai${path}`, {
    method,
    headers:{Authorization:`Bearer ${key}`,'Content-Type':'application/json'},
    body: body ? JSON.stringify(body) : undefined
  });
  const d = await r.json();
  if (!r.ok || (d.code && d.code !== 200)) throw new Error(d.msg || `KIE request failed (${r.status})`);
  return d;
}

async function groqModels() {
  const key = Deno.env.get('GROQ_API_KEY');
  if (!key) return [];
  try {
    const r = await fetch('https://api.groq.com/openai/v1/models',{headers:{Authorization:`Bearer ${key}`,'Content-Type':'application/json'}});
    if (!r.ok) return [];
    const d = await r.json();
    return (d.data||[]).filter((x:any)=>x.id&&!/whisper|guard|tts|speech|transcription/i.test(x.id)).map((x:any)=>({id:x.id,name:x.id,speed:/20b|8b|instant/i.test(x.id)?'Fast':/120b|qwen|compound|minimax/i.test(x.id)?'Expert':'Fast',provider:'Groq'}));
  } catch { return []; }
}

function normalize(type:string,d:any) {
  const data = d?.data || {};
  if (type === 'video') return {status:data.state||'pending',url:data.videoInfo?.videoUrl,urls:data.videoInfo?.videoUrl?[data.videoInfo.videoUrl]:[],raw:d};
  if (type === 'music') {
    const tracks = data.response?.sunoData || [];
    const urls = tracks.map((x:any)=>x.audio_url).filter(Boolean);
    return {status:data.status||'pending',url:urls[0],urls,raw:d};
  }
  const result = typeof data.resultJson === 'string' ? (()=>{try{return JSON.parse(data.resultJson)}catch{return {}}})() : data.resultJson || {};
  const urls = result.resultUrls || result.result_urls || result.urls || [];
  return {status:data.state||'pending',url:urls[0],urls,raw:d};
}

// These are current KIE model identifiers. The previous IDs in this function
// were aliases that KIE rejected with "model name ... is not supported".
const MODELS = {
  image:[
    {id:'seedream/5.0-lite',name:'Seedream 5 Lite',speed:'Fast',provider:'KIE'},
    {id:'seedream/5.0-pro',name:'Seedream 5 Pro',speed:'Expert',provider:'KIE'},
    {id:'google/imagen4-fast',name:'Imagen 4 Fast',speed:'Fast',provider:'KIE'},
    {id:'google/imagen4',name:'Imagen 4',speed:'Quality',provider:'KIE'},
    {id:'google/imagen4-ultra',name:'Imagen 4 Ultra',speed:'Expert',provider:'KIE'},
    {id:'google/nano-banana-2',name:'Nano Banana 2',speed:'Fast',provider:'KIE'},
    {id:'google/nano-banana-pro',name:'Nano Banana Pro',speed:'Expert',provider:'KIE'},
    {id:'flux-2/flex-text-to-image',name:'Flux 2 Flex',speed:'Fast',provider:'KIE'},
    {id:'flux-2/pro-text-to-image',name:'Flux 2 Pro',speed:'Quality',provider:'KIE'},
    {id:'grok-imagine/text-to-image',name:'Grok Imagine',speed:'Fast',provider:'KIE'},
    {id:'gpt-image-2',name:'GPT Image 2',speed:'Quality',provider:'KIE'}
  ],
  video:[
    {id:'kling-3.0/video',name:'Kling 3.0',speed:'Expert',provider:'KIE'},
    {id:'bytedance/seedance-2',name:'Seedance 2.0',speed:'Quality',provider:'KIE'},
    {id:'pixverse-v6/text-to-video',name:'PixVerse V6',speed:'Fast',provider:'KIE'},
    {id:'wan/2-7-text-to-video',name:'Wan 2.7',speed:'Fast',provider:'KIE'}
  ],
  music:[
    {id:'V6',name:'Suno V6',speed:'Expert',provider:'KIE'},
    {id:'V6_MINI',name:'Suno V6 Mini',speed:'Fast',provider:'KIE'},
    {id:'V6_WILD',name:'Suno V6 Wild',speed:'Creative',provider:'KIE'},
    {id:'V5_5',name:'Suno V5.5',speed:'Quality',provider:'KIE'},
    {id:'V5',name:'Suno V5',speed:'Fast',provider:'KIE'},
    {id:'V4_5ALL',name:'Suno V4.5 All',speed:'Fast',provider:'KIE'},
    {id:'V4_5PLUS',name:'Suno V4.5 Plus',speed:'Quality',provider:'KIE'}
  ]
};

function choose(type:string,mode:string,chat:any[]=[]) {
  if (type === 'chat') {
    if (mode === 'expert') return chat.find((x:any)=>x.id==='openai/gpt-oss-120b')?.id || 'openai/gpt-oss-120b';
    if (mode === 'fast') return chat.find((x:any)=>x.id==='openai/gpt-oss-20b')?.id || 'openai/gpt-oss-20b';
    return mode === 'auto' ? 'openai/gpt-oss-20b' : mode;
  }
  const list = (MODELS as any)[type] || [];
  if (mode === 'expert') return list.find((x:any)=>x.speed==='Expert'||x.speed==='Quality')?.id || list[0]?.id;
  if (mode === 'fast') return list.find((x:any)=>/Fast|Ultra Fast/.test(x.speed||''))?.id || list[0]?.id;
  if (mode === 'auto') return list[0]?.id;
  return mode || list[0]?.id;
}

serve(async req => {
  if (req.method === 'OPTIONS') return new Response('ok',{headers:cors});
  try {
    const body = await req.json();
    const {type,prompt,options={},action='generate',taskId} = body;
    const chat = action === 'models' ? await groqModels() : [];
    if (action === 'models') return json({models:MODELS,chat,presets:[{id:'auto',name:'Auto',speed:'Best fit'},{id:'fast',name:'Fast',speed:'Quick'},{id:'expert',name:'Expert',speed:'Highest quality'}]});

    const auth = req.headers.get('Authorization');
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const service = serviceKey ? createClient(Deno.env.get('SUPABASE_URL')!,serviceKey,{global:{headers:auth?{Authorization:auth}:{}}}) : null;
    let userId:string|null = null;
    if (service && auth) { const {data:{user}} = await service.auth.getUser(); userId = user?.id || null; }

    if (action === 'status') {
      if (!taskId) return json({error:'taskId is required'},400);
      const d = await kie(`/api/v1/jobs/recordInfo?taskId=${encodeURIComponent(taskId)}`,undefined,'GET');
      return json(normalize(type,d));
    }
    if (!prompt?.trim()) return json({error:'Prompt is required'},400);

    const callbackUrl = `${Deno.env.get('SUPABASE_URL')}/functions/v1/ai-callback`;

    if (type === 'image') {
      const model = choose('image',options.model||'auto');
      const d = await kie('/api/v1/jobs/createTask',{model,callBackUrl:callbackUrl,input:{prompt,aspect_ratio:options.aspectRatio||'1:1',resolution:options.resolution||'1K',nsfw_checker:false}});
      const id = d.data?.taskId;
      if (service && userId && id) await service.from('ai_generations').insert({user_id:userId,type:'image',prompt,model,task_id:id,status:'pending'});
      return json({taskId:id,status:'pending',model,raw:d});
    }

    if (type === 'video') {
      const model = choose('video',options.model||'auto');
      let input:any;
      if (model === 'kling-3.0/video') {
        input = {
          prompt,
          sound: options.generateAudio ?? false,
          duration: String(Math.min(15,Math.max(3,Number(options.duration||5)))),
          aspect_ratio: options.aspectRatio || '16:9',
          mode: options.quality === '1080p' ? 'pro' : 'std',
          multi_shots: false
        };
      } else if (model === 'bytedance/seedance-2') {
        input = {
          prompt,
          generate_audio: options.generateAudio ?? false,
          resolution: options.quality === '1080p' ? '1080p' : '720p',
          aspect_ratio: options.aspectRatio || '16:9',
          duration: Math.min(15,Math.max(5,Number(options.duration||5))),
          web_search: false
        };
      } else if (model === 'pixverse-v6/text-to-video') {
        input = {
          prompt,
          aspect_ratio: options.aspectRatio || '16:9',
          quality: options.quality === '1080p' ? '1080p' : '720p',
          duration: Math.min(8,Math.max(5,Number(options.duration||5))),
          generate_audio_switch: options.generateAudio ?? false,
          generate_multi_clip_switch: false
        };
      } else {
        input = {
          prompt,
          negative_prompt: options.negativePrompt || '',
          resolution: options.quality === '1080p' ? '1080p' : '720p',
          ratio: options.aspectRatio || '16:9',
          duration: Math.min(10,Math.max(5,Number(options.duration||5))),
          prompt_extend: true,
          watermark: false
        };
      }
      const d = await kie('/api/v1/jobs/createTask',{model,callBackUrl, input});
      const id = d.data?.taskId;
      if (service && userId && id) await service.from('ai_generations').insert({user_id:userId,type:'video',prompt,model,task_id:id,status:'pending'});
      return json({taskId:id,status:'pending',model,raw:d});
    }

    if (type === 'music') {
      const model = choose('music',options.model||'auto');
      const d = await kie('/api/v1/generate',{prompt,customMode:false,instrumental:options.instrumental??false,model,callBackUrl:callbackUrl});
      const id = d.data?.taskId;
      if (service && userId && id) await service.from('ai_generations').insert({user_id:userId,type:'music',prompt,model,task_id:id,status:'pending'});
      return json({taskId:id,status:'PENDING',model,raw:d});
    }

    const groq = Deno.env.get('GROQ_API_KEY');
    if (!groq) throw new Error('GROQ_API_KEY is not configured');
    const model = choose('chat',options.model||'auto',await groqModels());
    const r = await fetch('https://api.groq.com/openai/v1/chat/completions',{method:'POST',headers:{Authorization:`Bearer ${groq}`,'Content-Type':'application/json'},body:JSON.stringify({model,messages:[{role:'system',content:'You are GG AI, a fast, helpful and premium AI assistant inside GG Messenger. Give accurate, useful and well-structured answers.'},{role:'user',content:prompt}],temperature:0.7})});
    const d = await r.json();
    if (!r.ok) throw new Error(d.error?.message||'Groq AI request failed');
    return json({message:d.choices?.[0]?.message?.content||'',status:'success',model:d.model||model,raw:d});
  } catch(e) {
    return json({error:e instanceof Error?e.message:'AI generation failed'},500);
  }
});
