import { Hono } from 'hono';
import {extractStatementPDF, gmailJSON} from './statement-mailbox';
import { APIError, appSession, encrypt, decrypt, type KiteEnvironment } from './zerodha';
import type { GmailEnvironment } from './gmail';
import {parseHDFCStatement} from './hdfc-statement';
import {digest} from './zerodha';
import {portfolioTotals,type Portfolio} from './portfolio-valuation';
type Checkpoint = ReturnType<typeof parseHDFCStatement>;
type Settings = {encrypted_password:string;last_sync_at:number|null;error:string|null};
type Part = {filename?:string;mimeType?:string;body?:{attachmentId?:string;data?:string;size?:number};parts?:Part[];headers?:{name:string;value:string}[]};
const errorText='HDFC statement needs review. Check the PDF password and statement balance. Your previous FD balance is retained.';
export function trustedHDFCMessage(payload:Part) {
 const headers=payload.headers??[];
 const values=(name:string)=>headers.filter(h=>h.name.toLowerCase()===name).map(h=>h.value.trim());
 const from=values('from'),subject=values('subject');
 const auth=values('authentication-results').find(v=>/^mx\.google\.com\s*;/i.test(v));
 return from.length===1 && /^(?:[^<>]*<)?hdfcbanksmartstatement@hdfcbank\.bank\.in>?$/i.test(from[0])
 && subject.length===1 && /^HDFC Bank Combined Email Statement for [A-Za-z]+-\d{4}$/.test(subject[0])
 && !!auth && /dmarc=pass\b[^;]*\bheader\.from=hdfcbank\.bank\.in(?:\s|;|$)/i.test(auth);
}
function pdfs(part:Part):Part[] {
 return [...(part.filename?.toLowerCase().endsWith('.pdf') && ['application/pdf','application/octet-stream'].includes(part.mimeType??'') ? [part] : []),...(part.parts??[]).flatMap(pdfs)];
}
export async function extractHDFCPDF(bytes:Uint8Array,password:string) {return extractStatementPDF(bytes,password);}
export async function saveHDFCSnapshot(env:Pick<KiteEnvironment,'DB'>,owner:string,parsed:Checkpoint,message:string,hash:string,at:Date) {
 const previous=await env.DB.prepare('SELECT statement_date,content_hash FROM hdfc_snapshots WHERE owner_id=?').bind(owner).first<{statement_date:string;content_hash:string}>();
 const seen=await env.DB.prepare('SELECT status FROM hdfc_imports WHERE owner_id=? AND content_hash=?').bind(owner,hash).first<{status:string}>();
 if(seen && seen.status!=='needs_review')return 'duplicate';
 if(previous?.content_hash===hash) {
  await env.DB.prepare("INSERT INTO hdfc_imports(owner_id,content_hash,message_id,status,imported_at) VALUES(?,?,?,'imported',?) ON CONFLICT(owner_id,content_hash) DO UPDATE SET status='imported',error=NULL").bind(owner,hash,message,at.getTime()).run();
  return 'duplicate';
 }
 if(previous?.statement_date===parsed.date)throw new Error('Conflicting HDFC statement.');
 const status=previous && parsed.date<previous.statement_date?'ignored':'imported';
 if(status==='imported') {
  const deposits=await Promise.all(parsed.deposits.map(async({number,...terms})=>({...terms,id:await digest(owner+':hdfc:'+number),last4:number.slice(-4)})));
  await env.DB.prepare(`INSERT INTO hdfc_snapshots(owner_id,statement_date,total,deposits,message_id,content_hash,imported_at) VALUES(?,?,?,?,?,?,?)
   ON CONFLICT(owner_id) DO UPDATE SET statement_date=excluded.statement_date,total=excluded.total,deposits=excluded.deposits,message_id=excluded.message_id,content_hash=excluded.content_hash,imported_at=excluded.imported_at WHERE excluded.statement_date>hdfc_snapshots.statement_date`).bind(owner,parsed.date,parsed.total,JSON.stringify(deposits),message,hash,at.getTime()).run();
 }
 await env.DB.prepare('INSERT INTO hdfc_imports(owner_id,content_hash,message_id,status,imported_at) VALUES(?,?,?,?,?) ON CONFLICT(owner_id,content_hash) DO UPDATE SET status=excluded.status,error=NULL,imported_at=excluded.imported_at').bind(owner,hash,message,status,at.getTime()).run();
 return status;
}
export async function hdfcPortfolio(env:Pick<KiteEnvironment,'DB'>,snapshot:Portfolio,owner:string):Promise<Portfolio> {
 const row=await env.DB.prepare('SELECT statement_date,deposits FROM hdfc_snapshots WHERE owner_id=?').bind(owner).first<{statement_date:string;deposits:string}>();
 if(!row)return snapshot;
 const deposits=JSON.parse(row.deposits) as (Omit<Checkpoint['deposits'][number],'number'> & {id:string;last4:string})[];
 const holdings:Portfolio['holdings']=deposits.map(d=>({id:'hdfc:fd:'+d.id,name:'HDFC FD ••'+d.last4,symbol:'FD ••'+d.last4,assetClass:'fixedDeposit',accountID:'hdfc',quantity:'1',unit:'deposit',invested:'0',costBasisKnown:false,depositTerms:{originalPrincipal:d.originalPrincipal,currentAmount:d.currentAmount,maturityAmount:d.maturityAmount,rate:d.rate,openedOn:d.openedOn,maturesOn:d.maturesOn,lien:d.lien},value:d.withdrawable,gain:null,gainPercent:null,quote:d.withdrawable,quoteAt:row.statement_date+'T00:00:00Z',quoteCurrency:'INR',fxRate:'1',fxAt:null,history:[],source:'HDFC monthly combined statement',priceBasis:`Withdrawable value dated ${row.statement_date}. Rate ${d.rate}% p.a.; opened ${d.openedOn}; matures ${d.maturesOn}. Updated monthly; no estimated daily interest.`}));
 return portfolioTotals({...snapshot,holdings:[...snapshot.holdings.filter(h=>!h.id.startsWith('hdfc:fd:')), ...holdings],connections:[...snapshot.connections.filter(c=>c.id!=='hdfc'),{id:'hdfc',name:'HDFC Bank',symbol:'H',status:'connected',lastSyncAt:row.statement_date+'T00:00:00Z',description:'FD withdrawable balances from monthly statement dated '+row.statement_date}]});
}
export async function syncHDFC(env:GmailEnvironment,owner:string,fetcher:typeof fetch=fetch,at=new Date()) {
 const lease=at.getTime()+120000;
 const settings=await env.DB.prepare('UPDATE hdfc_settings SET lease_until=? WHERE owner_id=? AND lease_until<=? RETURNING encrypted_password,last_sync_at,error').bind(lease,owner,at.getTime()).first<Settings>();
 if(!settings)return {imported:0,skipped:true};
 let error:string|null=null;
 try {
  const gmail=await env.DB.prepare('SELECT encrypted_refresh_token FROM gmail_connections WHERE owner_id=?').bind(owner).first<{encrypted_refresh_token:string}>();
  if(!gmail)throw new APIError(409,'GMAIL_REQUIRED','Connect Gmail before syncing HDFC.');
  if(!env.GMAIL_CLIENT_ID || !env.GMAIL_CLIENT_SECRET)throw new APIError(503,'GMAIL_NOT_CONFIGURED','Gmail is not configured on the server.');
  const tokens=await gmailJSON(fetcher,'https://oauth2.googleapis.com/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({client_id:env.GMAIL_CLIENT_ID,client_secret:env.GMAIL_CLIENT_SECRET,refresh_token:await decrypt(gmail.encrypted_refresh_token,env.KITE_ENCRYPTION_KEY),grant_type:'refresh_token'})});
  if(typeof tokens.access_token!=='string' || !tokens.access_token)throw new Error('Missing Gmail token.');
  const headers={Authorization:'Bearer '+tokens.access_token};
  const query=new URLSearchParams({q:'from:hdfcbanksmartstatement@hdfcbank.bank.in subject:"HDFC Bank Combined Email Statement" has:attachment filename:pdf newer_than:120d',maxResults:'10'});
  const list=await gmailJSON(fetcher,'https://gmail.googleapis.com/gmail/v1/users/me/messages?'+query,{headers});
  if(!Array.isArray(list.messages) && list.messages!==undefined)throw new Error('Invalid mailbox response.');
  const messages=(list.messages??[]).slice(0,10);
  for(const message of messages) {
   if(typeof message.id!=='string' || !/^[a-zA-Z0-9_-]+$/.test(message.id))continue;
   const seen=await env.DB.prepare("SELECT status FROM hdfc_imports WHERE owner_id=? AND message_id=? AND status IN ('imported','ignored')").bind(owner,message.id).first();
   if(seen)continue;
   const detail=await gmailJSON(fetcher,`https://gmail.googleapis.com/gmail/v1/users/me/messages/${message.id}?format=full`,{headers});
   if(!trustedHDFCMessage(detail.payload??{}))throw new Error('Statement sender could not be verified.');
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
   const duplicate=await env.DB.prepare('SELECT status FROM hdfc_imports WHERE owner_id=? AND content_hash=?').bind(owner,hash).first<{status:string}>();
   if(duplicate && duplicate.status!=='needs_review')continue;
   try {
    const password=await decrypt(settings.encrypted_password,env.KITE_ENCRYPTION_KEY);
    const parsed=parseHDFCStatement(await extractHDFCPDF(bytes,password),at);
    const status=await saveHDFCSnapshot(env,owner,parsed,message.id,hash,at);
    return {imported:status==='imported'?1:0,status};
   }catch {
    await env.DB.prepare("INSERT INTO hdfc_imports(owner_id,content_hash,message_id,status,error,imported_at) VALUES(?,?,?,'needs_review',?,?) ON CONFLICT(owner_id,content_hash) DO UPDATE SET error=excluded.error").bind(owner,hash,message.id,errorText,at.getTime()).run();
    throw new APIError(409,'HDFC_REVIEW_REQUIRED',errorText);
   }
  }
  return {imported:0,status:'up_to_date'};
 }catch(failure){
  error=failure instanceof APIError ? failure.message : 'HDFC sync failed. Your previous FD balance is retained.';
  if(failure instanceof APIError && failure.code==='GMAIL_RECONNECT_REQUIRED')await env.DB.prepare("UPDATE gmail_connections SET status='reconnect',error=? WHERE owner_id=?").bind(error,owner).run();
  throw failure instanceof APIError ? failure : new APIError(502,'HDFC_SYNC_FAILED',error);
 }finally{await env.DB.prepare('UPDATE hdfc_settings SET lease_until=0,last_sync_at=?,error=? WHERE owner_id=? AND lease_until=?').bind(at.getTime(),error,owner,lease).run();}
}
export function hdfcRoutes(fetcher:typeof fetch=fetch,now=Date.now) {
 const app=new Hono<{Bindings:GmailEnvironment}>();
 app.onError((error,c)=>{const e=error instanceof APIError?error:new APIError(502,'HDFC_UNAVAILABLE','HDFC sync failed. Your previous FD balance is retained.');return c.json({error:{code:e.code,message:e.message}},e.status);});
 app.use('*',async(c,next)=>{c.header('Cache-Control','no-store');await next();});
 app.get('/status',async c=>{
  const auth=await appSession(c.env,c.req.header('Authorization'),now);
  const settings=await c.env.DB.prepare('SELECT last_sync_at,error FROM hdfc_settings WHERE owner_id=?').bind(auth.owner_id).first<{last_sync_at:number|null;error:string|null}>();
  const gmail=await c.env.DB.prepare("SELECT owner_id FROM gmail_connections WHERE owner_id=? AND status='connected'").bind(auth.owner_id).first();
  const balance=await c.env.DB.prepare('SELECT statement_date,total,json_array_length(deposits) AS count FROM hdfc_snapshots WHERE owner_id=?').bind(auth.owner_id).first();
  return c.json({configured:!!settings,gmailConnected:!!gmail,lastSyncAt:settings?.last_sync_at??null,error:settings?.error??null,balance:balance??null});
 });
 app.put('/password',async c=>{
  const auth=await appSession(c.env,c.req.header('Authorization'),now);
  const raw=await c.req.text();if(raw.length>512)throw new APIError(400,'INVALID_PASSWORD','Enter your HDFC Customer ID.');
  let password:unknown;try{password=JSON.parse(raw).password;}catch{}
  if(typeof password!=='string' || !/^[0-9]{6,20}$/.test(password))throw new APIError(400,'INVALID_PASSWORD','Enter your HDFC Customer ID.');
  await c.env.DB.prepare('INSERT INTO hdfc_settings(owner_id,encrypted_password,updated_at) VALUES(?,?,?) ON CONFLICT(owner_id) DO UPDATE SET encrypted_password=excluded.encrypted_password,updated_at=excluded.updated_at,error=NULL').bind(auth.owner_id,await encrypt(password,c.env.KITE_ENCRYPTION_KEY),now()).run();
  await c.env.DB.prepare("DELETE FROM hdfc_imports WHERE owner_id=? AND status='needs_review'").bind(auth.owner_id).run();
  return c.json({saved:true});
 });
 app.delete('/password',async c=>{
  const auth=await appSession(c.env,c.req.header('Authorization'),now);
  await c.env.DB.prepare('DELETE FROM hdfc_settings WHERE owner_id=?').bind(auth.owner_id).run();return c.json({removed:true});
 });
 app.post('/sync',async c=>{
  const auth=await appSession(c.env,c.req.header('Authorization'),now);
  if(!await c.env.DB.prepare('SELECT owner_id FROM hdfc_settings WHERE owner_id=?').bind(auth.owner_id).first())throw new APIError(409,'HDFC_PASSWORD_REQUIRED','Save your HDFC Customer ID first.');
  return c.json(await syncHDFC(c.env,auth.owner_id,fetcher,new Date(now())));
 });
 return app;
}
