import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type'};
const json=(x:any,status=200)=>new Response(JSON.stringify(x),{status,headers:{...cors,'Content-Type':'application/json'}});

serve(async req=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
  try{
    const auth=req.headers.get('Authorization');
    if(!auth)return json({error:'Unauthorized'},401);
    const userClient=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:auth}}});
    const {data:{user},error:userError}=await userClient.auth.getUser();
    if(userError||!user)return json({error:'Unauthorized'},401);

    const body=await req.json();
    const type=body.type as string;
    const prompt=String(body.prompt||'').trim();
    const model=body.model?String(body.model):null;
    const taskId=body.taskId?String(body.taskId):null;
    const urls=Array.isArray(body.urls)?body.urls.filter((x:any)=>typeof x==='string'):[];
    const resultText=body.resultText?String(body.resultText):null;
    if(!['chat','image','video','music'].includes(type)||!prompt)return json({error:'Invalid generation'},400);

    const service=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const saved:string[]=[];
    for(const url of urls){
      try{
        const r=await fetch(url);
        if(!r.ok)continue;
        const contentType=r.headers.get('content-type')||'application/octet-stream';
        const ext=contentType.includes('video')?'mp4':contentType.includes('audio')?'mp3':contentType.includes('png')?'png':contentType.includes('webp')?'webp':'jpg';
        const path=`${user.id}/${crypto.randomUUID()}.${ext}`;
        const bytes=new Uint8Array(await r.arrayBuffer());
        const up=await service.storage.from('ai-generations').upload(path,bytes,{contentType,cacheControl:'31536000',upsert:false});
        if(!up.error)saved.push(path);
      }catch(_e){}
    }
    const {data:row,error}=await service.from('ai_generations').insert({user_id:user.id,type,prompt,model,task_id:taskId,status:'completed',result_urls:saved,result_text:resultText,completed_at:new Date().toISOString()}).select('id,result_urls,result_text,created_at').single();
    if(error)throw error;
    return json({id:row.id,paths:row.result_urls,resultText:row.result_text,createdAt:row.created_at});
  }catch(e){return json({error:e instanceof Error?e.message:'Could not save generation'},500)}
});
