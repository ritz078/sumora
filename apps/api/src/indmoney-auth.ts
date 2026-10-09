import {Hono} from 'hono';
import {APIError,appSession,randomToken,digest,encrypt,decrypt,type KiteEnvironment} from './zerodha';
import {syncINDmoney} from './indmoney-portfolio';
import {boundedJSON} from './gold-prices';
export const IND_ENDPOINT='https://mcp.indmoney.com';
export const IND_CALLBACK='https://sumora-api.rkritesh078.workers.dev/v1/indmoney/callback';
export type IndCredentials={client_id:string;client_secret:string;access_token:string;refresh_token:string;expires_at:number};
type Attempt={id:string;owner_id:string;challenge:string;encrypted_verifier:string;encrypted_client:string;encrypted_credentials:string;expires_at:number};
export async function indJSON(fetcher:typeof fetch,path:string,init:RequestInit={}) {
 const response=await fetcher(IND_ENDPOINT+path,{...init,redirect:'manual',signal:AbortSignal.timeout(15000)});
 if(response.status===400 || response.status===401) {
  const payload=await boundedJSON(new Response(response.body,{status:200}),100000).catch(()=>({}));
  if(payload.error==='invalid_grant' || response.status===401)throw new APIError(409,'INDMONEY_RECONNECT_REQUIRED','Reconnect INDmoney to update US holdings.');
  throw new APIError(502,'INDMONEY_UNAVAILABLE','INDmoney could not complete the request.');
 }
 return boundedJSON(response,100000);
}
export async function indTokens(fetcher:typeof fetch,client:{client_id:string;client_secret:string},fields:Record<string,string>,at:number):Promise<IndCredentials> {
 const value=await indJSON(fetcher,'/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({...client,...fields})});
 if(typeof value.access_token!=='string' || !value.access_token || typeof value.expires_in!=='number' || !Number.isFinite(value.expires_in) || value.expires_in<=0 || value.expires_in>31536000 || typeof value.token_type!=='string' || value.token_type.toLowerCase()!=='bearer' || value.scope && !String(value.scope).split(' ').includes('portfolio:read'))throw new Error('Invalid INDmoney tokens');
 const refresh=value.refresh_token??fields.refresh_token;
 if(typeof refresh!=='string' || !refresh)throw new Error('INDmoney offline authorization is missing');
 return {...client,access_token:value.access_token,refresh_token:refresh,expires_at:at+value.expires_in*1000};
}
async function object(request:Request) {
 const raw=await request.text();if(raw.length>2048)throw new APIError(400,'INVALID_REQUEST','Request too large.');
 try{const value=JSON.parse(raw);if(value && typeof value==='object' && !Array.isArray(value))return value;}catch{}
 throw new APIError(400,'INVALID_REQUEST','Expected a JSON object.');
}
export function indmoneyRoutes(fetcher:typeof fetch=fetch,now=Date.now) {
 const app=new Hono<{Bindings:KiteEnvironment}>();
 app.use('*',async(c,next)=>{c.header('Cache-Control','no-store');c.header('Referrer-Policy','no-referrer');await next();});
 app.onError((error,c)=>{const e=error instanceof APIError?error:new APIError(502,'INDMONEY_UNAVAILABLE','INDmoney is temporarily unavailable. Your previous holdings are retained.');return c.json({error:{code:e.code,message:e.message}},e.status);});
 app.post('/start',async c=>{
  const auth=await appSession(c.env,c.req.header('Authorization'),now),{challenge}=await object(c.req.raw);
  if(typeof challenge!=='string' || !/^[a-f0-9]{64}$/.test(challenge))throw new APIError(400,'INVALID_CHALLENGE','Invalid login challenge.');
  await c.env.DB.prepare('DELETE FROM indmoney_attempts WHERE expires_at<=?').bind(now()).run();
  const count=await c.env.DB.prepare('SELECT count(*) AS total FROM indmoney_attempts').first<{total:number}>();
  if((count?.total??0)>=50)throw new APIError(429,'LOGIN_BUSY','Try connecting again later.');
  const state=randomToken(),verifier=randomToken();
  const registered=await indJSON(fetcher,'/register',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({client_name:'Sumora',redirect_uris:[IND_CALLBACK],grant_types:['authorization_code','refresh_token'],response_types:['code'],token_endpoint_auth_method:'client_secret_post',scope:'portfolio:read'})});
  if(typeof registered.client_id!=='string' || !registered.client_id || typeof registered.client_secret!=='string' || !registered.client_secret || registered.token_endpoint_auth_method && registered.token_endpoint_auth_method!=='client_secret_post')throw new Error('Unsupported INDmoney registration');
  const client={client_id:registered.client_id,client_secret:registered.client_secret};
  await c.env.DB.prepare('INSERT INTO indmoney_attempts(id,owner_id,challenge,encrypted_verifier,encrypted_client,expires_at) VALUES(?,?,?,?,?,?)').bind(state,auth.owner_id,challenge,await encrypt(verifier,c.env.KITE_ENCRYPTION_KEY),await encrypt(JSON.stringify(client),c.env.KITE_ENCRYPTION_KEY),now()+600000).run();
  const hash=await digest(verifier),pkce=btoa(String.fromCharCode(...Uint8Array.from(hash.match(/../g)!,v=>parseInt(v,16)))).replaceAll('+','-').replaceAll('/','_').replaceAll('=','');
  const params=new URLSearchParams({client_id:client.client_id,redirect_uri:IND_CALLBACK,response_type:'code',scope:'portfolio:read',state,code_challenge:pkce,code_challenge_method:'S256',resource:IND_ENDPOINT+'/mcp'});
  return c.json({state,loginURL:IND_ENDPOINT+'/authorize?'+params});
 });
 app.get('/callback',async c=>{
  const state=c.req.query('state')??'',redirect=new URL('sumora://indmoney');redirect.searchParams.set('state',state);
  const attempt=await c.env.DB.prepare("UPDATE indmoney_attempts SET callback_claimed=1 WHERE id=? AND expires_at>? AND result_hash IS NULL AND callback_claimed=0 RETURNING *").bind(state,now()).first<Attempt>();
  if(!attempt) {redirect.searchParams.set('error','LOGIN_EXPIRED');return c.redirect(redirect.toString());}
  try {
   const code=c.req.query('code');
   if(c.req.query('error') || !code || code.length>2048)throw Error('Login cancelled');
   const client=JSON.parse(await decrypt(attempt.encrypted_client,c.env.KITE_ENCRYPTION_KEY));
   const credentials=await indTokens(fetcher,client,{grant_type:'authorization_code',code,redirect_uri:IND_CALLBACK,code_verifier:await decrypt(attempt.encrypted_verifier,c.env.KITE_ENCRYPTION_KEY),resource:IND_ENDPOINT+'/mcp'},now());
   const claim=randomToken();
   const updated=await c.env.DB.prepare("UPDATE indmoney_attempts SET result_hash=?,encrypted_credentials=?,encrypted_verifier='',expires_at=? WHERE id=? AND callback_claimed=1 AND result_hash IS NULL AND expires_at>? RETURNING id").bind(await digest(claim),await encrypt(JSON.stringify(credentials),c.env.KITE_ENCRYPTION_KEY),now()+60000,state,now()).first();
   if(!updated)throw Error('Expired login');
   redirect.searchParams.set('code',claim);
  } catch {
   await c.env.DB.prepare('DELETE FROM indmoney_attempts WHERE id=?').bind(state).run();
   redirect.searchParams.set('error','LOGIN_FAILED');
  }
  return c.redirect(redirect.toString());
 });
 app.post('/claim',async c=>{
  const auth=await appSession(c.env,c.req.header('Authorization'),now),{code,verifier}=await object(c.req.raw);
  if(typeof code!=='string' || !/^[a-f0-9]{64}$/.test(code) || typeof verifier!=='string' || !/^[a-zA-Z0-9_-]{43,128}$/.test(verifier))throw new APIError(401,'INVALID_LOGIN','Connect INDmoney again.');
  const attempt=await c.env.DB.prepare('DELETE FROM indmoney_attempts WHERE result_hash=? AND challenge=? AND owner_id=? AND expires_at>? AND encrypted_credentials IS NOT NULL RETURNING *').bind(await digest(code),await digest(verifier),auth.owner_id,now()).first<Attempt>();
  if(!attempt)throw new APIError(401,'INVALID_LOGIN','Connect INDmoney again.');
  await c.env.DB.prepare("INSERT INTO indmoney_connections(owner_id,generation,encrypted_credentials,connected_at) VALUES(?,?,?,?) ON CONFLICT(owner_id) DO UPDATE SET generation=excluded.generation,encrypted_credentials=excluded.encrypted_credentials,connected_at=excluded.connected_at,status='connected',error=NULL,lease_until=0").bind(auth.owner_id,randomToken(),attempt.encrypted_credentials,now()).run();
  // Discover the authorized tool schema without importing any speculative holdings fields.
  // Discovery failure must not discard an otherwise valid authorization.
  try {
   const credentials:IndCredentials=JSON.parse(await decrypt(attempt.encrypted_credentials,c.env.KITE_ENCRYPTION_KEY));
   const {indMCP}=await import('./indmoney-mcp');
   const client=await indMCP(credentials.access_token,fetcher);
   const tools=await client.tools();
   await c.env.DB.prepare('INSERT INTO indmoney_capabilities(id,schema,discovered_at) VALUES(1,?,?) ON CONFLICT(id) DO UPDATE SET schema=excluded.schema,discovered_at=excluded.discovered_at').bind(JSON.stringify(tools),now()).run();
  } catch { /* Schema discovery can be retried without asking the user to sign in again. */ }
  return c.json({connected:true});
 });
 app.post('/sync',async c=>{
  const auth=await appSession(c.env,c.req.header('Authorization'),now);
  return c.json(await syncINDmoney(c.env,auth.owner_id,fetcher,new Date(now())));
 });
 app.get('/connection',async c=>{
  const auth=await appSession(c.env,c.req.header('Authorization'),now);
  const row=await c.env.DB.prepare('SELECT status,last_sync_at,error FROM indmoney_connections WHERE owner_id=?').bind(auth.owner_id).first<{status:string;last_sync_at:number|null;error:string|null}>();
  return c.json({connected:!!row,status:row?.status??'disconnected',lastSyncAt:row?.last_sync_at??null,error:row?.error??null});
 });
 app.delete('/connection',async c=>{
  const auth=await appSession(c.env,c.req.header('Authorization'),now);
  const row=await c.env.DB.prepare('DELETE FROM indmoney_connections WHERE owner_id=? RETURNING encrypted_credentials').bind(auth.owner_id).first<{encrypted_credentials:string}>();
  await c.env.DB.prepare('DELETE FROM indmoney_attempts WHERE owner_id=?').bind(auth.owner_id).run();
  await c.env.DB.prepare('DELETE FROM indmoney_snapshots WHERE owner_id=?').bind(auth.owner_id).run();
  if(row)try{const credentials:IndCredentials=JSON.parse(await decrypt(row.encrypted_credentials,c.env.KITE_ENCRYPTION_KEY));await indJSON(fetcher,'/revoke',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({client_id:credentials.client_id,client_secret:credentials.client_secret,token:credentials.refresh_token,token_type_hint:'refresh_token'})});}catch{/* Local unlink succeeds even if upstream revocation is unavailable. */}
  return c.json({disconnected:true});
 });
 return app;
}
