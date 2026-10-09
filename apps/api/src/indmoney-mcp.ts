import {APIError,encrypt,decrypt,type KiteEnvironment} from './zerodha';
import {IND_ENDPOINT,indTokens,type IndCredentials} from './indmoney-auth';
import {boundedJSON} from './gold-prices';
type Tool={name:string;description?:string;inputSchema:Record<string,unknown>};
const unavailable=()=>new APIError(502,'INDMONEY_UNAVAILABLE','INDmoney could not read your US holdings. Your previous data is retained.');
async function rpcResult(response:Response,id:number) {
 if(response.status===401){await response.body?.cancel();throw new APIError(409,'INDMONEY_RECONNECT_REQUIRED','Reconnect INDmoney to update US holdings.');}
 if(!response.ok){await response.body?.cancel();throw unavailable();}
 if(!response.headers.get('Content-Type')?.includes('text/event-stream'))return boundedJSON(response,2*1024*1024);
 if(!response.body)throw unavailable();
 const reader=response.body.getReader(),decoder=new TextDecoder();let buffer='',size=0;
 try {
  while(true) {
   const {done,value}=await reader.read();if(done)break;
   size+=value.length;if(size>2*1024*1024)throw unavailable();
   buffer+=decoder.decode(value,{stream:true});buffer=buffer.replaceAll('\r\n','\n');
   let end:number;
   while((end=buffer.indexOf('\n\n'))>=0) {
    const event=buffer.slice(0,end);buffer=buffer.slice(end+2);
    const data=event.split('\n').filter(l=>l.startsWith('data:')).map(l=>l.slice(5).trimStart()).join('\n');
    if(!data)continue;
    const message=JSON.parse(data);if(message.id===id)return message;
   }
  }
 }finally{await reader.cancel();}
 throw unavailable();
}
export async function indMCP(token:string,fetcher:typeof fetch=fetch) {
 let counter=0,session:string|null=null,protocol='2025-03-26';
 async function request(method:string,params?:unknown,notification=false):Promise<any> {
  const id=++counter,headers:Record<string,string>={Authorization:'Bearer '+token,'Content-Type':'application/json',Accept:'application/json, text/event-stream','MCP-Protocol-Version':protocol};
  if(session)headers['Mcp-Session-Id']=session;
  const response=await fetcher(IND_ENDPOINT+'/mcp',{method:'POST',headers,body:JSON.stringify({jsonrpc:'2.0',...(notification?{}:{id}),method,...(params===undefined?{}:{params})}),redirect:'manual',signal:AbortSignal.timeout(15000)});
  if(notification){await response.body?.cancel();if(!response.ok)throw unavailable();return;}
  const message=await rpcResult(response,id);
  if(message.jsonrpc!=='2.0' || message.id!==id || message.error || !message.result || typeof message.result!=='object')throw unavailable();
  const returnedSession=response.headers.get('Mcp-Session-Id');if(returnedSession){if(returnedSession.length>512 || /[\r\n]/.test(returnedSession))throw unavailable();session=returnedSession;}
  return message.result;
 }
 const initialized=await request('initialize',{protocolVersion:protocol,capabilities:{},clientInfo:{name:'Sumora',version:'1.0'}});
 if(!['2024-11-05','2025-03-26','2025-06-18','2025-11-25'].includes(initialized.protocolVersion))throw unavailable();protocol=initialized.protocolVersion;
 await request('notifications/initialized',undefined,true);
 return {
  async tools():Promise<Tool[]> {
   const tools:Tool[]=[];let cursor:string|undefined;
   for(let page=0;page<5;page++) {
    const result=await request('tools/list',cursor?{cursor}:{});
    if(!Array.isArray(result.tools) || result.tools.some((t:any)=>typeof t.name!=='string' || !t.inputSchema || typeof t.inputSchema!=='object'))throw unavailable();
    tools.push(...result.tools);if(!result.nextCursor)return tools;
    if(typeof result.nextCursor!=='string')throw unavailable();cursor=result.nextCursor;
   }
   throw unavailable();
  },
  async call(name:string,args:Record<string,unknown>) {
   const result=await request('tools/call',{name,arguments:args});
   if(result.isError)throw unavailable();return result;
  }
 };
}
export async function withIndConnection<T>(env:KiteEnvironment,owner:string,operation:(token:string)=>Promise<T>,fetcher:typeof fetch=fetch,now=Date.now):Promise<T> {
 const lease=now()+300000;
 const row=await env.DB.prepare('UPDATE indmoney_connections SET lease_until=? WHERE owner_id=? AND lease_until<=? RETURNING generation,encrypted_credentials').bind(lease,owner,now()).first<{generation:string;encrypted_credentials:string}>();
 if(!row)throw new APIError(409,'INDMONEY_BUSY','Connect INDmoney or wait for the current sync to finish.');
 let error:string|null=null,status='connected';
 try {
  let credentials:IndCredentials=JSON.parse(await decrypt(row.encrypted_credentials,env.KITE_ENCRYPTION_KEY));
  const refresh=async()=>{
   credentials=await indTokens(fetcher,{client_id:credentials.client_id,client_secret:credentials.client_secret},{grant_type:'refresh_token',refresh_token:credentials.refresh_token,resource:IND_ENDPOINT+'/mcp'},now());
   const saved=await env.DB.prepare('UPDATE indmoney_connections SET encrypted_credentials=? WHERE owner_id=? AND generation=? AND lease_until=? RETURNING owner_id').bind(await encrypt(JSON.stringify(credentials),env.KITE_ENCRYPTION_KEY),owner,row.generation,lease).first();
   if(!saved)throw new APIError(409,'INDMONEY_CONNECTION_CHANGED','INDmoney connection changed. Try again.');
  };
  let refreshed=false;
  if(credentials.expires_at<=now()+60000){await refresh();refreshed=true;}
  try{return await operation(credentials.access_token);}catch(failure){
   if(!refreshed && failure instanceof APIError && failure.code==='INDMONEY_RECONNECT_REQUIRED'){await refresh();return await operation(credentials.access_token);}
   throw failure;
  }
 }catch(failure){
  if(failure instanceof APIError && failure.code==='INDMONEY_RECONNECT_REQUIRED')status='reconnect';
  error=failure instanceof APIError?failure.message:unavailable().message;
  throw failure instanceof APIError?failure:unavailable();
 }finally {
  await env.DB.prepare('UPDATE indmoney_connections SET lease_until=0,status=?,error=? WHERE owner_id=? AND generation=? AND lease_until=?').bind(status,error,owner,row.generation,lease).run();
 }
}
