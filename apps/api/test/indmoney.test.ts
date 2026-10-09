import {test} from 'node:test';
import assert from 'node:assert/strict';
import {setupGold} from './helpers/database';
import {digest,decrypt} from '../src/zerodha';
import {indmoneyRoutes} from '../src/indmoney-auth';
const at=Date.parse('2026-10-09T18:00:00Z'),key=Buffer.alloc(32,1).toString('base64');
test('INDmoney OAuth requires owner sign-in and verifier-bound single-use claims with encrypted server credentials',async()=>{
 const {db,env:base}=setupGold(),token='d'.repeat(64),verifier='v'.repeat(64);
 const env={...base,KITE_ENCRYPTION_KEY:key};
 db.prepare('INSERT INTO zerodha_sessions VALUES(?,?,?,?,?)').run(await digest(token),'unused','owner',at+86400000,0);
 const fetcher:typeof fetch=async(url,options)=>{
  if(String(url).endsWith('/register'))return Response.json({client_id:'client',client_secret:'client-secret',token_endpoint_auth_method:'client_secret_post'});
  if(String(url).endsWith('/mcp')) {
   const rpc=JSON.parse(String(options?.body));
   if(rpc.method==='notifications/initialized')return new Response(null,{status:202});
   return Response.json({jsonrpc:'2.0',id:rpc.id,result:rpc.method==='initialize'?{protocolVersion:'2025-03-26'}:{tools:[{name:'networth_holdings',inputSchema:{type:'object'}}]}});
  }
  assert.equal(String(url),'https://mcp.indmoney.com/token');
  const fields=new URLSearchParams(String(options?.body));
  assert.equal(fields.get('client_secret'),'client-secret');assert.ok(fields.get('code_verifier'));
  return Response.json({access_token:'access',refresh_token:'refresh',token_type:'Bearer',expires_in:3600,scope:'portfolio:read'});
 };
 const app=indmoneyRoutes(fetcher,()=>at);
 const req=(path:string,method='GET',body?:unknown,auth=true)=>app.request(path,{method,headers:{'Content-Type':'application/json',...(auth?{Authorization:'Bearer '+token}:{})},body:body?JSON.stringify(body):undefined},env as any);
 assert.equal((await req('/start','POST',{challenge:await digest(verifier)},false)).status,401);
 const start=await (await req('/start','POST',{challenge:await digest(verifier)})).json();
 const login=new URL(start.loginURL);assert.equal(login.origin,'https://mcp.indmoney.com');assert.equal(login.searchParams.get('scope'),'portfolio:read');assert.equal(login.searchParams.get('code_challenge_method'),'S256');
 const callback=await req('/callback?'+new URLSearchParams({state:start.state,code:'broker-code'}));
 const location=new URL(callback.headers.get('location')!);assert.equal(location.host,'indmoney');
 const code=location.searchParams.get('code');assert.ok(code);
 assert.equal((await req('/claim','POST',{code,verifier:'wrong'.repeat(13)})).status,401);
 assert.equal((await req('/claim','POST',{code,verifier})).status,200);
 assert.equal((await req('/claim','POST',{code,verifier})).status,401);
 const row=db.prepare('SELECT encrypted_credentials FROM indmoney_connections').get()!;
 const credentials=JSON.parse(await decrypt(String(row.encrypted_credentials),key));assert.equal(credentials.refresh_token,'refresh');
 assert.ok(!String(row.encrypted_credentials).includes('client-secret'));
 const capabilities=JSON.parse(String(db.prepare('SELECT schema FROM indmoney_capabilities').get()!.schema));assert.equal(capabilities[0].name,'networth_holdings');
 const status=await (await req('/connection')).text();assert.ok(!status.includes('refresh_token'));assert.ok(!status.includes('client-secret'));
 assert.equal((await req('/callback?state=unknown&code=evil')).status,302);
});

import {indMCP,withIndConnection} from '../src/indmoney-mcp';
import {encrypt} from '../src/zerodha';
test('INDmoney MCP handles JSON and SSE results and propagates read-only tool errors',async()=>{
 const fetcher:typeof fetch=async(_url,options)=>{
  const request=JSON.parse(String(options?.body));
  if(request.method==='notifications/initialized')return new Response(null,{status:202});
  if(request.method==='initialize')return Response.json({jsonrpc:'2.0',id:request.id,result:{protocolVersion:'2025-03-26',capabilities:{tools:{}},serverInfo:{name:'INDmoney',version:'1'}}},{headers:{'Mcp-Session-Id':'session'}});
  assert.equal(new Headers(options?.headers).get('Mcp-Session-Id'),'session');
  if(request.method==='tools/list')return new Response('event: message\ndata: '+JSON.stringify({jsonrpc:'2.0',id:request.id,result:{tools:[{name:'networth_holdings',inputSchema:{type:'object'}}]}})+'\n\n',{headers:{'Content-Type':'text/event-stream'}});
  return Response.json({jsonrpc:'2.0',id:request.id,result:{isError:true,content:[{type:'text',text:'private upstream detail'}]}});
 };
 const client=await indMCP('access',fetcher);
 assert.equal((await client.tools())[0].name,'networth_holdings');
 await assert.rejects(()=>client.call('networth_holdings',{}),/could not read/i);
});
test('INDmoney rotates encrypted refresh credentials under a lease and retains the connection after transient errors',async()=>{
 const {db,env:base}=setupGold();const env={...base,KITE_ENCRYPTION_KEY:key} as any;
 const initial={client_id:'client',client_secret:'secret',access_token:'old-access',refresh_token:'old-refresh',expires_at:at-1};
 db.prepare('INSERT INTO indmoney_connections(owner_id,generation,encrypted_credentials,connected_at) VALUES(?,?,?,?)').run('owner','generation',await encrypt(JSON.stringify(initial),key),at);
 const fetcher:typeof fetch=async()=>Response.json({access_token:'new-access',refresh_token:'new-refresh',token_type:'Bearer',expires_in:3600});
 const result=await withIndConnection(env,'owner',async token=>token,fetcher,()=>at);
 assert.equal(result,'new-access');
 const saved=JSON.parse(await decrypt(String(db.prepare('SELECT encrypted_credentials FROM indmoney_connections').get()!.encrypted_credentials),key));
 assert.equal(saved.refresh_token,'new-refresh');
 await assert.rejects(()=>withIndConnection(env,'owner',async()=>{throw Error('temporary');},fetcher,()=>at));
 assert.equal(db.prepare('SELECT status FROM indmoney_connections').get()?.status,'connected');
 assert.equal(db.prepare('SELECT lease_until FROM indmoney_connections').get()?.lease_until,0);
 await assert.rejects(()=>withIndConnection(env,'other',async()=>null,fetcher,()=>at));
});

import {APIError} from '../src/zerodha';
test('INDmoney refuses overlapping refresh, marks revoked access for reconnect and cannot overwrite a newer connection',async()=>{
 const {db,env:base}=setupGold(),env={...base,KITE_ENCRYPTION_KEY:key} as any;
 const initial={client_id:'client',client_secret:'secret',access_token:'access',refresh_token:'refresh',expires_at:at+3600000};
 const encrypted=await encrypt(JSON.stringify(initial),key);
 db.prepare('INSERT INTO indmoney_connections(owner_id,generation,encrypted_credentials,connected_at) VALUES(?,?,?,?)').run('owner','old',encrypted,at);
 await withIndConnection(env,'owner',async()=>{
  await assert.rejects(()=>withIndConnection(env,'owner',async()=>null,fetch,()=>at),(e:any)=>e.code==='INDMONEY_BUSY');
  return true;
 },fetch,()=>at);
 await assert.rejects(()=>withIndConnection(env,'owner',async()=>{throw new APIError(409,'INDMONEY_RECONNECT_REQUIRED','expired');},async()=>Response.json({error:'invalid_grant'},{status:400}),()=>at));
 assert.equal(db.prepare('SELECT status FROM indmoney_connections').get()?.status,'reconnect');
 await assert.rejects(()=>withIndConnection(env,'owner',async()=>{throw new APIError(409,'INDMONEY_RECONNECT_REQUIRED','expired');},async()=>{
  db.prepare("UPDATE indmoney_connections SET generation='new',encrypted_credentials=?,lease_until=0,status='connected'").run(encrypted);
  return Response.json({access_token:'stale-access',refresh_token:'stale-refresh',token_type:'Bearer',expires_in:3600});
 },()=>at),(e:any)=>e.code==='INDMONEY_CONNECTION_CHANGED');
 const row=db.prepare('SELECT generation,encrypted_credentials,status FROM indmoney_connections').get()!;
 assert.equal(row.generation,'new');assert.equal(row.encrypted_credentials,encrypted);assert.equal(row.status,'connected');
});

import {app} from '../src/index';
test('INDmoney is mounted in the API and personal connection endpoints require authentication',async()=>{
 for(const [path,method] of [['/connection','GET'],['/connection','DELETE'],['/start','POST'],['/claim','POST'],['/sync','POST']]) {
  const response=await app.request('/v1/indmoney'+path,{method,headers:{'Content-Type':'application/json'},body:method==='POST'?'{}':undefined},{} as any);
  assert.equal(response.status,401);
 }
});
