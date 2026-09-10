import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';

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

serve(async req=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
  try{
    const body=await req.json();
    const {type,prompt,options={},action='generate',taskId}=body;

    if(action==='status'){
      if(!taskId)return json({error:'taskId is required'},400);
      let d;
      if(type==='video')d=await kie(`/api/v1/runway/record-detail?taskId=${encodeURIComponent(taskId)}`,undefined,'GET');
      else if(type==='music')d=await kie(`/api/v1/generate/record-info?taskId=${encodeURIComponent(taskId)}`,undefined,'GET');
      else d=await kie(`/api/v1/jobs/recordInfo?taskId=${encodeURIComponent(taskId)}`,undefined,'GET');
      return json(normalizeStatus(type,d));
    }

    if(!prompt?.trim())return json({error:'Prompt is required'},400);
    if(type==='image'){
      const d=await kie('/api/v1/jobs/createTask',{model:options.model||'flux-2/flex-text-to-image',input:{prompt,aspect_ratio:options.aspectRatio||'1:1',resolution:'1K',nsfw_checker:false}});
      return json({taskId:d.data?.taskId,status:'pending',raw:d});
    }
    if(type==='video'){
      const d=await kie('/api/v1/runway/generate',{prompt,duration:options.duration||5,quality:options.quality||'720p',aspectRatio:options.aspectRatio||'9:16',waterMark:''});
      return json({taskId:d.data?.taskId,status:'wait',raw:d});
    }
    if(type==='music'){
      const d=await kie('/api/v1/generate',{prompt,customMode:false,instrumental:false,model:options.model||'V5_5'});
      return json({taskId:d.data?.taskId,status:'PENDING',raw:d});
    }

    const openai=Deno.env.get('OPENAI_API_KEY');
    if(!openai)throw new Error('OPENAI_API_KEY is not configured');
    const r=await fetch('https://api.openai.com/v1/responses',{method:'POST',headers:{Authorization:`Bearer ${openai}`,'Content-Type':'application/json'},body:JSON.stringify({model:'gpt-5.6',input:prompt})});
    const d=await r.json();
    if(!r.ok)throw new Error(d.error?.message||'AI request failed');
    return json({message:d.output_text||d.output?.map((x:any)=>x.content?.map((c:any)=>c.text).join('')).join('')||'',status:'success',raw:d});
  }catch(e){return json({error:e instanceof Error?e.message:'AI generation failed'},500)}
});
