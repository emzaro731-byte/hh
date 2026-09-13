type Listener=()=>void;
let listener:Listener|null=null;
export const onOpenCommunity=(next:Listener)=>{listener=next;return()=>{if(listener===next)listener=null}};
export const openCommunity=()=>{listener?.()};
