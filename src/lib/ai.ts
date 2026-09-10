import {supabase} from './supabase';

export type AIGeneration={taskId?:string;status?:string;url?:string;urls?:string[];message?:string;raw?:any;model?:string};

export async function generateAI(type:'chat'|'image'|'video'|'music',prompt:string,options:any={}):Promise<AIGeneration>{
  const {data,error}=await supabase.functions.invoke('ai-generate',{body:{type,prompt,options}});
  if(error)throw error;
  if(data?.error)throw new Error(data.error);
  return data as AIGeneration;
}

export async function getAIStatus(type:'image'|'video'|'music',taskId:string):Promise<AIGeneration>{
  const {data,error}=await supabase.functions.invoke('ai-generate',{body:{action:'status',type,taskId}});
  if(error)throw error;
  if(data?.error)throw new Error(data.error);
  return data as AIGeneration;
}

export async function waitForAI(type:'image'|'video'|'music',taskId:string,onUpdate?:(value:AIGeneration)=>void):Promise<AIGeneration>{
  const started=Date.now();let delay=2500;
  while(Date.now()-started<15*60*1000){
    const value=await getAIStatus(type,taskId);onUpdate?.(value);
    const state=(value.status||'').toLowerCase();
    if(value.url||value.urls?.length||['success','succeeded','complete','completed','first_success'].includes(state))return value;
    if(['fail','failed','create_task_failed','generate_audio_failed','sensitive_word_error'].includes(state))throw new Error(value.raw?.data?.errorMessage||'Generation failed');
    await new Promise(resolve=>setTimeout(resolve,delay));delay=Math.min(Math.round(delay*1.25),10000);
  }
  throw new Error('Generation timed out. Please try again.');
}

export async function saveAIGeneration(type:'chat'|'image'|'video'|'music',prompt:string,result:AIGeneration,model?:string){
  const urls=result.urls?.length?result.urls:(result.url?[result.url]:[]);
  const {data,error}=await supabase.functions.invoke('ai-save',{body:{type,prompt,model,taskId:result.taskId,urls,resultText:result.message}});
  if(error)throw error;
  if(data?.error)throw new Error(data.error);
  return data;
}

export async function loadAIHistory(limit=20){
  const {data,error}=await supabase.from('ai_generations').select('id,type,prompt,model,task_id,status,result_urls,result_text,created_at,completed_at').order('created_at',{ascending:false}).limit(limit);
  if(error)throw error;
  return data??[];
}
