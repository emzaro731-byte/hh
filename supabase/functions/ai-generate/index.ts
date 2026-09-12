import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type'};
const json=(x:any,status=200)=>new Response(JSON.stringify(x),{status,headers:{...cors,'Content-Type':'application/json'}});

async function kie(path:string,body?:any,method='POST'){
  const key=Deno.env.get('KIE_API_KEY');
  if(!key)throw new Error('KIE_API_KEY is not configured');
  const r=await fetch(`https://api.kie.ai${path}`,{method,headers:{Authorization:`Bearer ${key}`,'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined});
  const d=await r.json();
  if(!r.ok||d.code&&d.code!==200)throw new Error(d.msg||`KIE request failed (${r.status})`);
  return d;
}

function normalizeStatus(type:string,d:any){
  const data=d?.data||{};
  if(type==='video')return {status:data.state||'pending',url:data.videoInfo?.videoUrl,urls:data.videoInfo?.videoUrl?[data.videoInfo.videoUrl]:[],raw:d};
  if(type==='music'){
    const tracks=data.response?.sunoData||[];
    const urls=tracks.map((x:any)=>x.audio_url).filter(Boolean);
    return {status:data.status||'pending',url:urls[0],urls,raw:d};
  }
  const result=typeof data.resultJson==='string'?(()=>{try{return JSON.parse(data.resultJson)}catch{return {}}})():data.resultJson||{};
  const urls=result.resultUrls||result.result_urls||result.urls||[];
  return {status:data.state||'pending',url:urls[0],urls,raw:d};
}

// KIE model catalog exposed to the app. KIE continually adds models, so the UI
// can offer these stable model IDs while the backend keeps provider secrets private.
const MODELS={
  image:[
    {id:'seedream/5.0-lite',name:'Seedream 5.0 Lite',speed:'Fast'},
    {id:'seedream/5.0-pro',name:'Seedream 5.0 Pro',speed:'Quality'},
    {id:'google/imagen4-fast',name:'Google Imagen 4 Fast',speed:'Fast'},
    {id:'google/imagen4',name:'Google Imagen 4',speed:'Quality'},
    {id:'google/nano-banana-2',name:'Nano Banana 2',speed:'Fast'},
    {id:'google/nano-banana-pro',name:'Nano Banana Pro',speed:'Quality'},
    {id:'flux-2/flex-text-to-image',name:'Flux 2 Flex',speed:'Fast'},
    {id:'flux-2/pro-text-to-image',name:'Flux 2 Pro',speed:'Quality'},
    {id:'grok-imagine/text-to-image',name:'Grok Imagine',speed:'Fast'},
    {id:'gpt-image-2',name:'GPT Image 2',speed:'Quality'},
    {id:'z-image',name:'Z-image',speed:'Fast'},
  ],
  video:[
    {id:'kling-3.0',name:'Kling 3.0',speed:'Quality'},
    {id:'kling/v3-turbo-text-to-video',name:'Kling V3 Turbo',speed:'Fast'},
    {id:'kling-2.6/text-to-video',name:'Kling 2.6',speed:'Fast'},
    {id:'veo3/veo-3.1-fast',name:'Veo 3.1 Fast',speed:'Fast'},
    {id:'veo3/veo-3.1-quality',name:'Veo 3.1 Quality',speed:'Quality'},
    {id:'pixverse/v6-text-to-video',name:'PixVerse V6',speed:'Fast'},
    {id:'wan/2.7-text-to-video',name:'Wan 2.7',speed:'Fast'},
    {id:'runway',name:'Runway',speed:'Quality'},
    {id:'grok-imagine/text-to-video',name:'Grok Imagine Video',speed:'Fast'},
    {id:'seedance/2.0',name:'Seedance 2.0',speed:'Fast'},
  ],
  music:[
    {id:'V6',name:'Suno V6',speed:'Quality'},
    {id:'V6_MINI',name:'Suno V6 Mini',speed:'Fast'},
    {id:'V6_WILD',name:'Suno V6 Wild',speed:'Creative'},
    {id:'V5_5',name:'Suno V5.5',speed:'Quality'},
    {id:'V5',name:'Suno V5',speed:'Fast'},
    {id:'V4_5ALL',name:'Suno V4.5 All',speed:'Fast'},
    {id:'V4_5PLUS',name:'Suno V4.5 Plus',speed:'Quality'},
    {id:'V4_5',name:'Suno V4.5',speed:'Fast'},
    {id:'V4',name:'Suno V4',speed:'Classic'},
  ]
};

serve(async req=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
  try{
    const body=await req.json();
    const {type,prompt,options={},action='generate',taskId}=body;
    if(action==='models')return json({models:MODELS});
    const auth=req.headers.get('Authorization');
    const serviceKey=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const service=serviceKey?createClient(Deno.env.get('SUPABASE_URL')!,serviceKey,{global:{headers:auth?{Authorization:auth}:{}}}):null;
    let userId:string|null=null;
    if(service&&auth){const {data:{user}}=await service.auth.getUser();userId=user?.id||null;}

    if(action==='status'){
      if(!taskId)return json({error:'taskId is required'},400);
      let d;
      if(type==='video'&&options.statusEndpoint)d=await kie(options.statusEndpoint,undefined,'GET');
      else if(type==='video'&&options.model?.startsWith('runway'))d=await kie(`/api/v1/runway/record-detail?taskId=${encodeURIComponent(taskId)}`,undefined,'GET');
      else if(type==='music')d=await kie(`/api/v1/generate/record-info?taskId=${encodeURIComponent(taskId)}`,undefined,'GET');
      else d=await kie(`/api/v1/jobs/recordInfo?taskId=${encodeURIComponent(taskId)}`,undefined,'GET');
      return json(normalizeStatus(type,d));
    }

    if(!prompt?.trim())return json({error:'Prompt is required'},400);
    const callbackUrl=`${Deno.env.get('SUPABASE_URL')}/functions/v1/ai-callback`;

    if(type==='image'){
      const model=options.model||'google/imagen4-fast';
      const d=await kie('/api/v1/jobs/createTask',{model,callBackUrl:callbackUrl,input:{prompt,aspect_ratio:options.aspectRatio||'1:1',resolution:options.resolution||'1K',nsfw_checker:false}});
      const id=d.data?.taskId;
      if(service&&userId&&id)await service.from('ai_generations').insert({user_id:userId,type:'image',prompt,model,task_id:id,status:'pending'});
      return json({taskId:id,status:'pending',model,raw:d});
    }
    if(type==='video'){
      const model=options.model||'kling/v3-turbo-text-to-video';
      if(model==='runway'){
        const d=await kie('/api/v1/runway/generate',{prompt,duration:options.duration||5,quality:options.quality||'720p',aspectRatio:options.aspectRatio||'9:16',waterMark:'',callBackUrl:callbackUrl});
        const id=d.data?.taskId;
        if(service&&userId&&id)await service.from('ai_generations').insert({user_id:userId,type:'video',prompt,model,task_id:id,status:'pending'});
        return json({taskId:id,status:'wait',model,raw:d});
      }
      const input:any={prompt,aspect_ratio:options.aspectRatio||'9:16',duration:options.duration||5,quality:options.quality||'720p'};
      if(model.includes('kling')||model.includes('pixverse'))input.generate_audio_switch=options.generateAudio??false;
      const d=await kie('/api/v1/jobs/createTask',{model,callBackUrl:callbackUrl,input});
      const id=d.data?.taskId;
      if(service&&userId&&id)await service.from('ai_generations').insert({user_id:userId,type:'video',prompt,model,task_id:id,status:'pending'});
      return json({taskId:id,status:'pending',model,raw:d});
    }
    if(type==='music'){
      const model=options.model||'V6_MINI';
      const d=await kie('/api/v1/generate',{prompt,customMode:false,instrumental:options.instrumental??false,model,callBackUrl:callbackUrl});
      const id=d.data?.taskId;
      if(service&&userId&&id)await service.from('ai_generations').insert({user_id:userId,type:'music',prompt,model,task_id:id,status:'pending'});
      return json({taskId:id,status:'PENDING',model,raw:d});
    }

    const groq=Deno.env.get('GROQ_API_KEY');
    if(!groq)throw new Error('GROQ_API_KEY is not configured');
    const model=options.model||'openai/gpt-oss-120b';
    const r=await fetch('https://api.groq.com/openai/v1/chat/completions',{method:'POST',headers:{Authorization:`Bearer ${groq}`,'Content-Type':'application/json'},body:JSON.stringify({model,messages:[{role:'system',content:'You are GG AI, a fast, helpful and premium AI assistant inside GG Messenger. Give accurate, useful and well-structured answers.'},{role:'user',content:prompt}],temperature:0.7})});
    const d=await r.json();
    if(!r.ok)throw new Error(d.error?.message||'Groq AI request failed');
    return json({message:d.choices?.[0]?.message?.content||'',status:'success',model:d.model||model,raw:d});
  }catch(e){return json({error:e instanceof Error?e.message:'AI generation failed'},500)}
});
