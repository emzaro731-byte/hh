import {supabase} from './supabase';

export type AIGeneration={taskId?:string;status?:string;url?:string;urls?:string[];message?:string;raw?:any};

export async function generateAI(type:'chat'|'image'|'video'|'music',prompt:string,options:any={}):Promise<AIGeneration>{
  const {data,error}=await supabase.functions.invoke('ai-generate',{body:{type,prompt,options}});
  if(error)throw error;
  if(data?.error)throw new Error(data.error);
  return data as AIGeneration;
}
