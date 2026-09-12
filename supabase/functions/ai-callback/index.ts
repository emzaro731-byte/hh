import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const json=(x:any,status=200)=>new Response(JSON.stringify(x),{status,headers:{'Content-Type':'application/json'}});

function urlsFromCallback(body:any):string[]{
  const data=body?.data||{};
  const out:string[]=[];
  const add=(v:any)=>{if(typeof v==='string'&&/^https?:\/\//i.test(v)&&!out.includes(v))out.push(v)};
  add(data.video_url); add(data.videoUrl); add(data.videoInfo?.videoUrl);
  add(data.resultImageUrl); add(data.result_image_url); add(data.image_url);
  const result=typeof data.resultJson==='string'?(()=>{try{return JSON.parse(data.resultJson)}catch{return {}}})():data.resultJson||{};
  for(const key of ['resultUrls','result_urls','urls'])for(const v of (Array.isArray(result[key])?result[key]:[]))add(v);
  for(const track of (Array.isArray(data.data)?data.data:[])){add(track?.audio_url);add(track?.stream_audio_url);add(track?.video_url);add(track?.image_url);}
  for(const track of (Array.isArray(data.response?.sunoData)?data.response.sunoData:[])){add(track?.audio_url);add(track?.stream_audio_url);add(track?.image_url);}
  return out;
}

serve(async req=>{
  if(req.method==='OPTIONS')return new Response('ok');
  try{
    const body=await req.json();
    const taskId=String(body?.taskId||body?.data?.task_id||'').trim();
    if(!taskId)return json({error:'taskId is required'},400);
    const serviceKey=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if(!serviceKey)return json({error:'SUPABASE_SERVICE_ROLE_KEY is not configured'},500);
    const sb=createClient(Deno.env.get('SUPABASE_URL')!,serviceKey);
    const success=Number(body?.code)===200;
    const callbackType=String(body?.data?.callbackType||'complete').toLowerCase();
    const status=success?(callbackType==='first'?'processing':'completed'):'failed';
    const urls=urlsFromCallback(body);
    const resultText=String(body?.msg||'').slice(0,4000)||null;
    const update:any={status,result_urls:urls,completed_at:success&&callbackType!=='first'?new Date().toISOString():null,result_text:resultText};
    const {error}=await sb.from('ai_generations').update(update).eq('task_id',taskId);
    if(error)throw error;
    return json({received:true,taskId,status});
  }catch(e){return json({error:e instanceof Error?e.message:'Callback processing failed'},500)}
});
