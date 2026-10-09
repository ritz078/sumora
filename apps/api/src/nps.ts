import { Hono } from 'hono';
import {Decimal} from 'decimal.js';
import {extractStatementPDF, gmailJSON} from './statement-mailbox';
import { APIError, appSession, encrypt, decrypt, type KiteEnvironment } from './zerodha';
import type { GmailEnvironment } from './gmail';
import {parseNPSStatement} from './nps-statement';
import {digest} from './zerodha';
import {portfolioTotals,type Portfolio} from './portfolio-valuation';
type Checkpoint = ReturnType<typeof parseNPSStatement>;
type Settings = {encrypted_password:string|null;last_sync_at:number|null;error:string|null;scan_cursor:string|null};
type Part = {filename?:string;mimeType?:string;body?:{attachmentId?:string;data?:string;size?:number};parts?:Part[];headers?:{name:string;value:string}[]};
const errorText='NPS statement needs review. Check the PDF password and statement balance. Your previous NPS balance is retained.';
export function trustedNPSMessage(payload:Part) {
 const values=(name:string)=>(payload.headers??[]).filter(h=>h.name.toLowerCase()===name).map(h=>h.value.trim());
 const from=values('from'),subject=values('subject');
 const auth=values('authentication-results').filter(v=>/^mx\.google\.com\s*;/i.test(v));
 return from.length===1 && /^(?:[^<>]*<)?KCRA@kfintech\.com>?$/i.test(from[0]) && subject.length===1
 && /^(?:Monthly Transaction Statement for your NPS account with KFintech-CRA|Transaction Statement for NPS from KFintech-CRA)$/i.test(subject[0])
 && auth.length===1 && /dmarc=pass\b[^;]*\bheader\.from=kfintech\.com(?:\s|;|$)/i.test(auth[0]);
}
function pdfs(part:Part):Part[] {
 return [...(part.filename?.toLowerCase().endsWith('.pdf') && ['application/pdf','application/octet-stream'].includes(part.mimeType??'') ? [part] : []),...(part.parts??[]).flatMap(pdfs)];
}
export async function extractNPSPDF(bytes:Uint8Array,password:string) {return extractStatementPDF(bytes,password);}
export async function saveNPSSnapshot(env:Pick<KiteEnvironment,'DB'>,owner:string,parsed:Checkpoint,message:string,hash:string,at:Date,lease?:number) {
 if(lease!==undefined && !await env.DB.prepare('SELECT owner_id FROM nps_settings WHERE owner_id=? AND lease_until=?').bind(owner,lease).first())throw new Error('NPS settings changed during sync.');
 const previous=await env.DB.prepare('SELECT valuation_date,content_hash,account_hash FROM nps_snapshots WHERE owner_id=? AND tier=?').bind(owner,parsed.tier).first<{valuation_date:string;content_hash:string;account_hash:string}>();
 const seen=await env.DB.prepare('SELECT status FROM nps_imports WHERE owner_id=? AND content_hash=?').bind(owner,hash).first<{status:string}>();
 if(seen && seen.status!=='needs_review')return 'duplicate';
 if(previous?.content_hash===hash) {
  await env.DB.prepare("INSERT INTO nps_imports(owner_id,content_hash,message_id,status,imported_at) VALUES(?,?,?,'imported',?) ON CONFLICT(owner_id,content_hash) DO UPDATE SET status='imported',error=NULL").bind(owner,hash,message,at.getTime()).run();
  return 'duplicate';
 }
 const accountHash=await digest(owner+':nps:'+parsed.pran);
 if(previous && previous.account_hash!==accountHash)throw new Error('Different NPS account.');
 if(previous?.valuation_date===parsed.valuationDate)throw new Error('Conflicting NPS statement.');
 const status=previous && parsed.valuationDate<previous.valuation_date?'ignored':'imported';
 if(status==='imported') {
 const saved=await env.DB.prepare(`INSERT INTO nps_snapshots(owner_id,tier,account_hash,statement_date,valuation_date,total,schemes,message_id,content_hash,imported_at) SELECT ?,?,?,?,?,?,?,?,?,? WHERE (? IS NULL OR EXISTS(SELECT 1 FROM nps_settings WHERE owner_id=? AND lease_until=?))
 ON CONFLICT(owner_id,tier) DO UPDATE SET statement_date=excluded.statement_date,valuation_date=excluded.valuation_date,total=excluded.total,schemes=excluded.schemes,message_id=excluded.message_id,content_hash=excluded.content_hash,imported_at=excluded.imported_at WHERE excluded.valuation_date>nps_snapshots.valuation_date RETURNING content_hash`).bind(owner,parsed.tier,accountHash,parsed.statementDate,parsed.valuationDate,parsed.total,JSON.stringify(parsed.schemes),message,hash,at.getTime(),lease??null,owner,lease??null).first<{content_hash:string}>();
 if(!saved)throw new Error('NPS sync superseded.');
 }
 await env.DB.prepare('INSERT INTO nps_imports(owner_id,content_hash,message_id,status,imported_at) VALUES(?,?,?,?,?) ON CONFLICT(owner_id,content_hash) DO UPDATE SET status=excluded.status,error=NULL,imported_at=excluded.imported_at').bind(owner,hash,message,status,at.getTime()).run();
 return status;
}
export async function npsPortfolio(env:Pick<KiteEnvironment,'DB'>,snapshot:Portfolio,owner:string):Promise<Portfolio> {
 const result=await env.DB.prepare("SELECT json_group_array(json_object('tier',tier,'date',valuation_date,'schemes',json(schemes))) AS rows FROM nps_snapshots WHERE owner_id=?").bind(owner).first<{rows:string}>();
 const rows=JSON.parse(result?.rows??'[]') as {tier:string;date:string;schemes:Checkpoint['schemes']}[];
 if(!rows.length)return snapshot;
 const holdings:Portfolio['holdings']=rows.flatMap(row=>row.schemes.map(s=>({id:`nps:${row.tier}:${s.code}`,name:s.name.replace('NPS TRUST- A/C ','').replace('PENSION FUND MANAGEMENT LIMITED','').trim(),symbol:`Tier ${row.tier} · ${s.code}`,assetClass:'nps',accountID:'nps',quantity:s.quantity,unit:'units',invested:'0',costBasisKnown:false,value:s.value,gain:null,gainPercent:null,quote:s.nav,quoteAt:row.date+'T00:00:00Z',quoteCurrency:'INR',fxRate:'1',fxAt:null,history:[],source:'KFintech NPS statement',priceBasis:`Statement valuation as of ${row.date}. Updated when a new statement arrives; no live NAV or daily gain estimate.`})));
 const latest=rows.map(r=>r.date).sort().at(-1)!;
 return portfolioTotals({...snapshot,holdings:[...snapshot.holdings.filter(h=>!h.id.startsWith('nps:')),...holdings],connections:[...snapshot.connections.filter(c=>c.id!=='nps'),{id:'nps',name:'NPS · KFintech',symbol:'N',status:'connected',lastSyncAt:latest+'T00:00:00Z',description:'Statement balances as of '+latest}]});
}
export async function syncNPS(env:GmailEnvironment,owner:string,fetcher:typeof fetch=fetch,at=new Date()) {
 const lease=at.getTime()+120000;
 const settings=await env.DB.prepare('UPDATE nps_settings SET lease_until=? WHERE owner_id=? AND lease_until<=? RETURNING encrypted_password,last_sync_at,error,scan_cursor').bind(lease,owner,at.getTime()).first<Settings>();
 if(!settings)return {imported:0,skipped:true};
 let error:string|null=null;
 try {
  const gmail=await env.DB.prepare('SELECT encrypted_refresh_token FROM gmail_connections WHERE owner_id=?').bind(owner).first<{encrypted_refresh_token:string}>();
  if(!gmail)throw new APIError(409,'GMAIL_REQUIRED','Connect Gmail before syncing NPS.');
  if(!env.GMAIL_CLIENT_ID || !env.GMAIL_CLIENT_SECRET)throw new APIError(503,'GMAIL_NOT_CONFIGURED','Gmail is not configured on the server.');
  const tokens=await gmailJSON(fetcher,'https://oauth2.googleapis.com/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({client_id:env.GMAIL_CLIENT_ID,client_secret:env.GMAIL_CLIENT_SECRET,refresh_token:await decrypt(gmail.encrypted_refresh_token,env.KITE_ENCRYPTION_KEY),grant_type:'refresh_token'})});
  if(typeof tokens.access_token!=='string' || !tokens.access_token)throw new Error('Missing Gmail token.');
  const headers={Authorization:'Bearer '+tokens.access_token};
  const query=new URLSearchParams({q:'from:KCRA@kfintech.com {subject:"Monthly Transaction Statement" subject:"Transaction Statement for NPS"} has:attachment filename:pdf newer_than:120d',maxResults:'10'});
  if(settings.scan_cursor)query.set('pageToken',settings.scan_cursor);
  let list;
  try { list=await gmailJSON(fetcher,'https://gmail.googleapis.com/gmail/v1/users/me/messages?'+query,{headers}); }
  catch(failure) {
   if(settings.scan_cursor)await env.DB.prepare('UPDATE nps_settings SET scan_cursor=NULL WHERE owner_id=? AND lease_until=?').bind(owner,lease).run();
   throw failure;
  }
  if(!Array.isArray(list.messages) && list.messages!==undefined)throw new Error('Invalid mailbox response.');
  const messages=(list.messages??[]).slice(0,10);
  for(const message of messages) {
   if(typeof message.id!=='string' || !/^[a-zA-Z0-9_-]+$/.test(message.id))continue;
   const seen=await env.DB.prepare("SELECT status FROM nps_imports WHERE owner_id=? AND message_id=? AND status IN ('imported','ignored')").bind(owner,message.id).first();
   if(seen)continue;
   const detail=await gmailJSON(fetcher,`https://gmail.googleapis.com/gmail/v1/users/me/messages/${message.id}?format=full`,{headers});
   if(!trustedNPSMessage(detail.payload??{}))continue;
   const attachments=pdfs(detail.payload);
   if(attachments.length!==1)throw new Error('Expected one NPS statement PDF.');
   const part=attachments[0];
   if((part.body?.size??0)>2*1024*1024)throw new Error('Statement PDF too large.');
   let data=part.body?.data;
   if(!data && part.body?.attachmentId) {
    const id=part.body.attachmentId;if(!/^[a-zA-Z0-9_-]+$/.test(id))throw new Error('Invalid attachment.');
    const attachment=await gmailJSON(fetcher,`https://gmail.googleapis.com/gmail/v1/users/me/messages/${message.id}/attachments/${id}`,{headers});data=attachment.data;
   }
   if(typeof data!=='string' || data.length>2800000 || !/^[A-Za-z0-9_=-]+$/.test(data))throw new Error('Invalid attachment bytes.');
   const binary=atob(data.replaceAll('-','+').replaceAll('_','/'));const bytes=Uint8Array.from(binary,c=>c.charCodeAt(0));
   const hashBytes=await crypto.subtle.digest('SHA-256',bytes);const hash=Array.from(new Uint8Array(hashBytes),b=>b.toString(16).padStart(2,'0')).join('');
   const duplicate=await env.DB.prepare('SELECT status FROM nps_imports WHERE owner_id=? AND content_hash=?').bind(owner,hash).first<{status:string}>();
   if(duplicate && duplicate.status!=='needs_review')continue;
   try {
    const candidates=[...new Set<string>((detail.payload.headers??[]).filter((h:{name:string;value:string})=>h.name.toLowerCase()==='x-apiheader').map((h:{value:string})=>/^SCH_SOT_CRA_(\d{12})_\d+$/.exec(h.value.trim())?.[1]).filter((v:unknown):v is string=>typeof v==='string'))];
    const password=settings.encrypted_password?await decrypt(settings.encrypted_password,env.KITE_ENCRYPTION_KEY):candidates.length===1?candidates[0]:null;
    if(!password)throw new Error('NPS password required.');
    const parsed=parseNPSStatement(await extractNPSPDF(bytes,password),at);
    if(parsed.pran!==password)throw new Error('NPS account mismatch.');
    const status=await saveNPSSnapshot(env,owner,parsed,message.id,hash,at,lease);
    if(!settings.encrypted_password)await env.DB.prepare('UPDATE nps_settings SET encrypted_password=? WHERE owner_id=? AND lease_until=?').bind(await encrypt(password,env.KITE_ENCRYPTION_KEY),owner,lease).run();
    return {imported:status==='imported'?1:0,status};
   }catch {
    await env.DB.prepare("INSERT INTO nps_imports(owner_id,content_hash,message_id,status,error,imported_at) VALUES(?,?,?,'needs_review',?,?) ON CONFLICT(owner_id,content_hash) DO UPDATE SET error=excluded.error").bind(owner,hash,message.id,errorText,at.getTime()).run();
    throw new APIError(409,'NPS_REVIEW_REQUIRED',errorText);
   }
  }
  const next=typeof list.nextPageToken==='string' && list.nextPageToken.length<=1024?list.nextPageToken:null;
  await env.DB.prepare('UPDATE nps_settings SET scan_cursor=? WHERE owner_id=? AND lease_until=?').bind(next,owner,lease).run();
  return {imported:0,status:next?'scan_pending':'up_to_date'};
 }catch(failure){
  error=failure instanceof APIError ? failure.message : 'NPS sync failed. Your previous NPS balance is retained.';
  if(failure instanceof APIError && failure.code==='GMAIL_RECONNECT_REQUIRED')await env.DB.prepare("UPDATE gmail_connections SET status='reconnect',error=? WHERE owner_id=?").bind(error,owner).run();
  throw failure instanceof APIError ? failure : new APIError(502,'NPS_SYNC_FAILED',error);
 }finally{await env.DB.prepare('UPDATE nps_settings SET lease_until=0,last_sync_at=?,error=? WHERE owner_id=? AND lease_until=?').bind(at.getTime(),error,owner,lease).run();}
}
export function npsRoutes(fetcher:typeof fetch=fetch,now=Date.now) {
 const app=new Hono<{Bindings:GmailEnvironment}>();
 app.onError((error,c)=>{const e=error instanceof APIError?error:new APIError(502,'NPS_UNAVAILABLE','NPS sync failed. Your previous NPS balance is retained.');return c.json({error:{code:e.code,message:e.message}},e.status);});
 app.use('*',async(c,next)=>{c.header('Cache-Control','no-store');await next();});
 app.get('/status',async c=>{
  const auth=await appSession(c.env,c.req.header('Authorization'),now);
  const settings=await c.env.DB.prepare('SELECT last_sync_at,error FROM nps_settings WHERE owner_id=?').bind(auth.owner_id).first<{last_sync_at:number|null;error:string|null}>();
  const gmail=await c.env.DB.prepare("SELECT owner_id FROM gmail_connections WHERE owner_id=? AND status='connected'").bind(auth.owner_id).first();
  const recorded=await c.env.DB.prepare("SELECT json_group_array(json_object('date',valuation_date,'total',total,'schemes',json(schemes))) AS rows FROM nps_snapshots WHERE owner_id=?").bind(auth.owner_id).first<{rows:string}>();
  const rows=JSON.parse(recorded?.rows??'[]') as {date:string;total:string;schemes:unknown[]}[];
  const balance=rows.length?{statement_date:rows.map(r=>r.date).sort()[0],count:rows.reduce((n,r)=>n+r.schemes.length,0),total:rows.reduce((s,r)=>s.plus(r.total),new Decimal(0)).toFixed()}:null;
  return c.json({configured:!!settings,gmailConnected:!!gmail,lastSyncAt:settings?.last_sync_at??null,error:settings?.error??null,balance:balance??null});
 });
 app.put('/connection',async c=>{
  const auth=await appSession(c.env,c.req.header('Authorization'),now);
  await c.env.DB.prepare('INSERT INTO nps_settings(owner_id,updated_at) VALUES(?,?) ON CONFLICT(owner_id) DO NOTHING').bind(auth.owner_id,now()).run();return c.json({saved:true});
 });
 app.put('/password',async c=>{
  const auth=await appSession(c.env,c.req.header('Authorization'),now);
  const raw=await c.req.text();if(raw.length>512)throw new APIError(400,'INVALID_PASSWORD','Enter your 12-digit PRAN.');
  let password:unknown;try{password=JSON.parse(raw).password;}catch{}
  if(typeof password!=='string' || !/^[0-9]{12}$/.test(password))throw new APIError(400,'INVALID_PASSWORD','Enter your 12-digit PRAN.');
  await c.env.DB.prepare('INSERT INTO nps_settings(owner_id,encrypted_password,updated_at) VALUES(?,?,?) ON CONFLICT(owner_id) DO UPDATE SET encrypted_password=excluded.encrypted_password,updated_at=excluded.updated_at,error=NULL,lease_until=0,scan_cursor=NULL').bind(auth.owner_id,await encrypt(password,c.env.KITE_ENCRYPTION_KEY),now()).run();
  await c.env.DB.prepare("DELETE FROM nps_imports WHERE owner_id=? AND status='needs_review'").bind(auth.owner_id).run();
  return c.json({saved:true});
 });
 app.delete('/connection',async c=>{
  const auth=await appSession(c.env,c.req.header('Authorization'),now);
  await c.env.DB.prepare('DELETE FROM nps_settings WHERE owner_id=?').bind(auth.owner_id).run();return c.json({removed:true});
 });
 app.post('/sync',async c=>{
  const auth=await appSession(c.env,c.req.header('Authorization'),now);
  if(!await c.env.DB.prepare('SELECT owner_id FROM nps_settings WHERE owner_id=?').bind(auth.owner_id).first())throw new APIError(409,'NPS_PASSWORD_REQUIRED','Enable NPS imports first.');
  return c.json(await syncNPS(c.env,auth.owner_id,fetcher,new Date(now())));
 });
 return app;
}
