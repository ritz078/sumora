import { Hono } from 'hono';
import { Decimal } from 'decimal.js';
import { extractText, getDocumentProxy } from 'unpdf';
import { APIError, appSession, encrypt, decrypt, type KiteEnvironment } from './zerodha';
import type { GmailEnvironment } from './gmail';
import { boundedJSON, refreshGoldPrice } from './gold-prices';
import { parseGullakStatement } from './gullak-statement';
type Checkpoint = ReturnType<typeof parseGullakStatement>;
type Settings = {encrypted_password:string;last_sync_at:number|null;error:string|null};
type Part = {filename?:string;mimeType?:string;body?:{attachmentId?:string;data?:string;size?:number};parts?:Part[];headers?:{name:string;value:string}[]};
const errorText='Gullak statement needs review. Check the PDF password and statement balance. Your previous gold balance is retained.';
export function trustedGullakMessage(payload:Part) {
 const headers=payload.headers??[];
 const header=(name:string)=>headers.filter(h=>h.name.toLowerCase()===name).map(h=>h.value);
 const from=header('from'),subject=header('subject');
 const auth=header('authentication-results').find(v=>/^mx\.google\.com\s*;/i.test(v.trim()));
 return from.length===1 && /^(?:[^<>]*<)?no-reply@gullak\.money>?$/i.test(from[0].trim())
  && subject.length===1 && /^Gullak\s*:\s*Monthly Statement$/i.test(subject[0].trim())
  && !!auth && /dmarc=pass\b[^;]*\bheader\.from=gullak\.money(?:\s|;|$)/i.test(auth);
}
function pdfs(part:Part):Part[] {
 return [...(part.filename?.toLowerCase().endsWith('.pdf') && part.mimeType==='application/pdf' ? [part] : []),...(part.parts??[]).flatMap(pdfs)];
}
export async function extractGullakPDF(bytes:Uint8Array,password:string) {
 if(bytes.length>2*1024*1024 || new TextDecoder().decode(bytes.subarray(0,5))!=='%PDF-')throw new Error('Invalid PDF.');
 const pdf=await getDocumentProxy(bytes,{password,verbosity:0,useSystemFonts:false,disableFontFace:true});
 try {if(pdf.numPages>10)throw new Error('Statement too long.');const {text}=await extractText(pdf,{mergePages:true});if(text.length>150000)throw new Error('Statement too long.');return text;}finally{await pdf.loadingTask.destroy();}
}
export async function saveCheckpoint(env:Pick<KiteEnvironment,'DB'>,owner:string,parsed:Checkpoint,message:string,hash:string,at:Date) {
 const seen=await env.DB.prepare('SELECT status FROM gullak_imports WHERE owner_id=? AND content_hash=?').bind(owner,hash).first<{status:string}>();
 if(seen && seen.status!=='needs_review')return 'duplicate';
 const previous=await env.DB.prepare('SELECT * FROM gullak_checkpoints WHERE owner_id=?').bind(owner).first<{grams:string;period_end:string;balance_date:string;content_hash:string}>();
 let status='imported';
 if(previous && parsed.periodEnd<previous.period_end)status='ignored';
 else if(previous && previous.content_hash!==hash) {
  const nextDay=new Date(previous.period_end+'T00:00:00Z');nextDay.setUTCDate(nextDay.getUTCDate()+1);
  if(parsed.periodStart!==nextDay.toISOString().slice(0,10) || !new Decimal(parsed.openingGrams).eq(previous.grams) || parsed.balanceDate<previous.balance_date)throw new Error('Statement continuity needs review.');
 }
 if(status==='imported')await env.DB.prepare(`INSERT INTO gullak_checkpoints(owner_id,grams,opening_grams,period_start,period_end,balance_date,message_id,content_hash,imported_at) VALUES(?,?,?,?,?,?,?,?,?)
  ON CONFLICT(owner_id) DO UPDATE SET grams=excluded.grams,opening_grams=excluded.opening_grams,period_start=excluded.period_start,period_end=excluded.period_end,balance_date=excluded.balance_date,message_id=excluded.message_id,content_hash=excluded.content_hash,imported_at=excluded.imported_at
  WHERE excluded.period_end>gullak_checkpoints.period_end`).bind(owner,parsed.grams,parsed.openingGrams,parsed.periodStart,parsed.periodEnd,parsed.balanceDate,message,hash,at.getTime()).run();
 await env.DB.prepare('INSERT INTO gullak_imports(owner_id,content_hash,message_id,status,imported_at) VALUES(?,?,?,?,?) ON CONFLICT(owner_id,content_hash) DO UPDATE SET status=excluded.status,error=NULL,imported_at=excluded.imported_at').bind(owner,hash,message,status,at.getTime()).run();
 return status;
}
async function gmailJSON(fetcher:typeof fetch,url:string,init:RequestInit={}) {
 const response=await fetcher(url,{...init,signal:AbortSignal.timeout(15000),redirect:'manual'});
 if(response.status===401 || response.status===400 && url.includes('oauth2'))throw new APIError(409,'GMAIL_RECONNECT_REQUIRED','Reconnect Gmail to import Gullak statements.');
 return boundedJSON(response,4*1024*1024);
}
export async function syncGullak(env:GmailEnvironment,owner:string,fetcher:typeof fetch=fetch,at=new Date()) {
 const lease=at.getTime()+120000;
 const settings=await env.DB.prepare('UPDATE gullak_settings SET lease_until=? WHERE owner_id=? AND lease_until<=? RETURNING encrypted_password,last_sync_at,error').bind(lease,owner,at.getTime()).first<Settings>();
 if(!settings)return {imported:0,skipped:true};
 let error:string|null=null;
 try {
  const gmail=await env.DB.prepare('SELECT encrypted_refresh_token FROM gmail_connections WHERE owner_id=?').bind(owner).first<{encrypted_refresh_token:string}>();
  if(!gmail)throw new APIError(409,'GMAIL_REQUIRED','Connect Gmail before syncing Gullak.');
  if(!env.GMAIL_CLIENT_ID || !env.GMAIL_CLIENT_SECRET)throw new APIError(503,'GMAIL_NOT_CONFIGURED','Gmail is not configured on the server.');
  const tokens=await gmailJSON(fetcher,'https://oauth2.googleapis.com/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({client_id:env.GMAIL_CLIENT_ID,client_secret:env.GMAIL_CLIENT_SECRET,refresh_token:await decrypt(gmail.encrypted_refresh_token,env.KITE_ENCRYPTION_KEY),grant_type:'refresh_token'})});
  if(typeof tokens.access_token!=='string' || !tokens.access_token)throw new Error('Missing Gmail token.');
  const headers={Authorization:'Bearer '+tokens.access_token};
  const query=new URLSearchParams({q:'from:no-reply@gullak.money subject:"Gullak : Monthly Statement" has:attachment filename:pdf newer_than:120d',maxResults:'10'});
  const list=await gmailJSON(fetcher,'https://gmail.googleapis.com/gmail/v1/users/me/messages?'+query,{headers});
  if(!Array.isArray(list.messages) && list.messages!==undefined)throw new Error('Invalid mailbox response.');
  const existing=await env.DB.prepare('SELECT period_end FROM gullak_checkpoints WHERE owner_id=?').bind(owner).first();
  const messages=(list.messages??[]).slice(0,10);
  if(existing)messages.reverse(); // Fill consecutive months in order after the first checkpoint.
  for(const message of messages) {
   if(typeof message.id!=='string' || !/^[a-zA-Z0-9_-]+$/.test(message.id))continue;
   const seen=await env.DB.prepare("SELECT status FROM gullak_imports WHERE owner_id=? AND message_id=? AND status IN ('imported','ignored')").bind(owner,message.id).first();
   if(seen)continue;
   const detail=await gmailJSON(fetcher,`https://gmail.googleapis.com/gmail/v1/users/me/messages/${message.id}?format=full`,{headers});
   if(!trustedGullakMessage(detail.payload??{}))throw new Error('Statement sender could not be verified.');
   const attachments=pdfs(detail.payload);
   if(attachments.length!==1)throw new Error('Expected one monthly statement PDF.');
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
   const duplicate=await env.DB.prepare('SELECT status FROM gullak_imports WHERE owner_id=? AND content_hash=?').bind(owner,hash).first<{status:string}>();
   if(duplicate && duplicate.status!=='needs_review')continue;
   try {
    const password=await decrypt(settings.encrypted_password,env.KITE_ENCRYPTION_KEY);
    const parsed=parseGullakStatement(await extractGullakPDF(bytes,password),at);
    const status=await saveCheckpoint(env,owner,parsed,message.id,hash,at);
    return {imported:status==='imported'?1:0,status};
   }catch {
    await env.DB.prepare("INSERT INTO gullak_imports(owner_id,content_hash,message_id,status,error,imported_at) VALUES(?,?,?,'needs_review',?,?) ON CONFLICT(owner_id,content_hash) DO UPDATE SET error=excluded.error").bind(owner,hash,message.id,errorText,at.getTime()).run();
    throw new APIError(409,'GULLAK_REVIEW_REQUIRED',errorText);
   }
  }
  return {imported:0,status:'up_to_date'};
 }catch(failure){
  error=failure instanceof APIError ? failure.message : 'Gullak sync failed. Your previous gold balance is retained.';
  if(failure instanceof APIError && failure.code==='GMAIL_RECONNECT_REQUIRED')await env.DB.prepare("UPDATE gmail_connections SET status='reconnect',error=? WHERE owner_id=?").bind(error,owner).run();
  throw failure instanceof APIError ? failure : new APIError(502,'GULLAK_SYNC_FAILED',error);
 }finally{await env.DB.prepare('UPDATE gullak_settings SET lease_until=0,last_sync_at=?,error=? WHERE owner_id=? AND lease_until=?').bind(at.getTime(),error,owner,lease).run();}
}
export function gullakRoutes(fetcher:typeof fetch=fetch,now=Date.now) {
 const app=new Hono<{Bindings:GmailEnvironment}>();
 app.onError((error,c)=>{const failure=error instanceof APIError?error:new APIError(502,'GOLD_UNAVAILABLE','Gold could not be updated. Try again later.');return c.json({error:{code:failure.code,message:failure.message}},failure.status);});
 app.use('*',async(c,next)=>{c.header('Cache-Control','no-store');await next();});
 app.get('/status',async c=>{
  const auth=await appSession(c.env,c.req.header('Authorization'),now);
  const settings=await c.env.DB.prepare('SELECT last_sync_at,error FROM gullak_settings WHERE owner_id=?').bind(auth.owner_id).first<{last_sync_at:number|null;error:string|null}>();
  const gmail=await c.env.DB.prepare('SELECT owner_id FROM gmail_connections WHERE owner_id=?').bind(auth.owner_id).first();
  const balance=await c.env.DB.prepare('SELECT grams,balance_date,period_end FROM gullak_checkpoints WHERE owner_id=?').bind(auth.owner_id).first();
  const quote=await c.env.DB.prepare("SELECT price,date,source FROM market_prices WHERE kind='gold'").first();
  const job=await c.env.DB.prepare('SELECT error FROM gold_price_job WHERE id=1').first<{error:string|null}>();
  return c.json({configured:!!settings,gmailConnected:!!gmail,lastSyncAt:settings?.last_sync_at??null,error:settings?.error??null,balance:balance??null,quote:quote??null,priceError:job?.error??null});
 });
 app.put('/password',async c=>{
  const auth=await appSession(c.env,c.req.header('Authorization'),now);
  const raw=await c.req.text();if(raw.length>512)throw new APIError(400,'INVALID_MOBILE','Enter your 10-digit Gullak mobile number.');
  let mobile:unknown;try{mobile=JSON.parse(raw).mobile;}catch{}
  if(typeof mobile!=='string' || !/^[6-9][0-9]{9}$/.test(mobile))throw new APIError(400,'INVALID_MOBILE','Enter your 10-digit Gullak mobile number.');
  const password=await encrypt(mobile.slice(1,-1),c.env.KITE_ENCRYPTION_KEY);
  await c.env.DB.prepare('INSERT INTO gullak_settings(owner_id,encrypted_password,updated_at) VALUES(?,?,?) ON CONFLICT(owner_id) DO UPDATE SET encrypted_password=excluded.encrypted_password,updated_at=excluded.updated_at,error=NULL').bind(auth.owner_id,password,now()).run();
  // Permit retry of documents that failed with the previous password.
  await c.env.DB.prepare("DELETE FROM gullak_imports WHERE owner_id=? AND status='needs_review'").bind(auth.owner_id).run();
  return c.json({saved:true});
 });
 app.delete('/password',async c=>{
  const auth=await appSession(c.env,c.req.header('Authorization'),now);
  await c.env.DB.prepare('DELETE FROM gullak_settings WHERE owner_id=?').bind(auth.owner_id).run();
  return c.json({removed:true});
 });
 app.post('/sync',async c=>{
  const auth=await appSession(c.env,c.req.header('Authorization'),now);
  const settings=await c.env.DB.prepare('SELECT owner_id FROM gullak_settings WHERE owner_id=?').bind(auth.owner_id).first();
  if(!settings)throw new APIError(409,'GULLAK_PASSWORD_REQUIRED','Save your Gullak mobile number to decrypt statements.');
  const result=await syncGullak(c.env,auth.owner_id,fetcher,new Date(now()));
  await refreshGoldPrice(c.env,fetcher,new Date(now()));
  return c.json(result);
 });
 return app;
}
export async function scheduledGullak(env:GmailEnvironment,fetcher:typeof fetch=fetch,at=new Date()) {
 const rows=await env.DB.prepare("SELECT json_group_array(owner_id) AS owners FROM (SELECT s.owner_id FROM gullak_settings s JOIN gmail_connections g ON s.owner_id=g.owner_id WHERE g.status='connected' ORDER BY COALESCE(s.last_sync_at,0) LIMIT 1)").first<{owners:string}>();
 for(const owner of JSON.parse(rows?.owners??'[]').slice(0,3)) {
  try{await syncGullak(env,owner,fetcher,at);}catch{/* Per-account error is persisted; other accounts can proceed. */}
 }
}
