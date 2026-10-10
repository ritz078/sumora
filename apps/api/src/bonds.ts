import {syncWintBatch} from './wint-sync';
import {readWintEvents} from './wint-events';
import {reconcileBonds} from './bond-reconciliation';
import {Decimal} from 'decimal.js';
import {Hono} from 'hono';
import {extractStatementPDF,gmailJSON} from './statement-mailbox';
import {APIError,appSession,encrypt,decrypt,digest,type KiteEnvironment} from './zerodha';
import type {GmailEnvironment} from './gmail';
import {parseBondStatement} from './bond-statement';
import {portfolioTotals,type Portfolio} from './portfolio-valuation';
import {istDate} from './daily-prices';
type Checkpoint=ReturnType<typeof parseBondStatement>;
type Settings={encrypted_password:string;scan_cursor:string|null;wint_cursor:string|null;scan_kind:string};
type Part={filename?:string;mimeType?:string;body?:{attachmentId?:string;data?:string;size?:number};parts?:Part[];headers?:{name:string;value:string}[]};
const errorText='Bond statement needs review. Check the PAN and CAS balances. Your previous bond balances are retained.';
export function trustedBondMessage(payload:Part) {
 const values=(name:string)=>(payload.headers??[]).filter(h=>h.name.toLowerCase()===name).map(h=>h.value.trim());
 const from=values('from'),subject=values('subject'),auth=values('authentication-results').filter(v=>/^mx\.google\.com\s*;/i.test(v));
 return from.length===1 && /^(?:[^<>]*<)?eCAS@cdslstatement\.com>?$/i.test(from[0]) && subject.length===1
 && /^CDSL Consolidated Account Statement \(CAS\) across Mutual Funds and Depositories for-[A-Z]{3}\d{4}-[A-Z0-9-]+$/i.test(subject[0])
 && auth.length===1 && /dmarc=pass\b[^;]*\bheader\.from=cdslstatement\.com(?:\s|;|$)/i.test(auth[0]);
}
function pdfs(part:Part):Part[] {
 return [...(part.filename?.toLowerCase().endsWith('.pdf') && ['application/pdf','application/octet-stream','bin'].includes(part.mimeType??'')?[part]:[]),...(part.parts??[]).flatMap(pdfs)];
}
export async function saveBondSnapshot(env:Pick<KiteEnvironment,'DB'>,owner:string,parsed:Checkpoint,message:string,hash:string,at:Date,lease?:number) {
 if(lease!==undefined && !await env.DB.prepare('SELECT owner_id FROM bonds_settings WHERE owner_id=? AND lease_until=?').bind(owner,lease).first())throw new Error('Bond settings changed during sync.');
 const previous=await env.DB.prepare('SELECT statement_date,content_hash,account_hash FROM bonds_snapshots WHERE owner_id=?').bind(owner).first<{statement_date:string;content_hash:string;account_hash:string}>();
 const accountHash=await digest(owner+':bonds:'+parsed.accountID);
 if(previous && previous.account_hash!==accountHash)throw new Error('Different bond account.');
 let status='imported';
 if(previous?.content_hash===hash)status='duplicate';
 else if(previous?.statement_date===parsed.statementDate)throw new Error('Conflicting CAS.');
 else if(previous && previous.statement_date>parsed.statementDate)status='ignored';
 if(status==='imported') {
  const saved=await env.DB.prepare(`INSERT INTO bonds_snapshots(owner_id,account_hash,statement_date,total,bonds,message_id,content_hash,imported_at) SELECT ?,?,?,?,?,?,?,? WHERE (? IS NULL OR EXISTS(SELECT 1 FROM bonds_settings WHERE owner_id=? AND lease_until=?))
  ON CONFLICT(owner_id) DO UPDATE SET statement_date=excluded.statement_date,total=excluded.total,bonds=excluded.bonds,message_id=excluded.message_id,content_hash=excluded.content_hash,imported_at=excluded.imported_at WHERE excluded.statement_date>bonds_snapshots.statement_date RETURNING content_hash`).bind(owner,accountHash,parsed.statementDate,parsed.total,JSON.stringify(parsed.bonds),message,hash,at.getTime(),lease??null,owner,lease??null).first();
  if(!saved)throw new Error('Bond sync superseded.');
  // The snapshot trigger records the successful import in this same transaction.
  return status;
 }
 const recorded=await env.DB.prepare(`INSERT INTO bonds_imports(owner_id,content_hash,message_id,status,imported_at) SELECT ?,?,?,?,? WHERE (? IS NULL OR EXISTS(SELECT 1 FROM bonds_settings WHERE owner_id=? AND lease_until=?)) ON CONFLICT(owner_id,content_hash) DO UPDATE SET status=excluded.status,error=NULL RETURNING content_hash`).bind(owner,hash,message,status==='duplicate'?'imported':status,at.getTime(),lease??null,owner,lease??null).first();
 if(!recorded)throw new Error('Bond sync superseded.');
 return status;
}
export async function recordedBonds(env:Pick<KiteEnvironment,'DB'>,owner:string,at=new Date()) {
 const row=await env.DB.prepare('SELECT statement_date,bonds,account_hash,total FROM bonds_snapshots WHERE owner_id=?').bind(owner).first<{statement_date:string;bonds:string;account_hash:string;total:string}>();
 const result=reconcileBonds(row?{accountID:'',statementDate:row.statement_date,total:row.total,bonds:JSON.parse(row.bonds)}:null,row?.account_hash??null,await readWintEvents(env,owner),at);
 return {...result,statementDate:row?.statement_date??null};
}
export async function bondsPortfolio(env:Pick<KiteEnvironment,'DB'>,snapshot:Portfolio,owner:string,at=new Date()):Promise<Portfolio> {
 const result=await recordedBonds(env,owner,at);
 if(!result.statementDate)return snapshot;
 const attention=result.holdings.some(h=>h.bondTerms?.redemptionCheck || h.bondTerms?.reconciliationNote);
 return portfolioTotals({...snapshot,holdings:[...snapshot.holdings.filter(h=>!h.id.startsWith('bonds:')),...result.holdings],connections:[...snapshot.connections.filter(c=>c.id!=='bonds'),{id:'bonds',name:'Bonds · CDSL CAS',symbol:'B',status:attention?'attention':'connected',lastSyncAt:result.statementDate+'T00:00:00Z',description:attention?'CAS holdings as of '+result.statementDate+'. Maturity projections used where available; some bonds need reconciliation.':'CAS holdings as of '+result.statementDate+'; maturity projections used where available, otherwise statement value.'}]});
}
export async function syncBonds(env:GmailEnvironment,owner:string,fetcher:typeof fetch=fetch,at=new Date()):Promise<{imported:number;status?:string;skipped?:boolean}> {
 const lease=at.getTime()+120000;
 const settings=await env.DB.prepare('UPDATE bonds_settings SET lease_until=? WHERE owner_id=? AND lease_until<=? RETURNING encrypted_password,last_sync_at,error,scan_cursor,wint_cursor,scan_kind').bind(lease,owner,at.getTime()).first<Settings>();
 if(!settings)return {imported:0,skipped:true};
 let error:string|null=null;
 try {
  const gmail=await env.DB.prepare('SELECT encrypted_refresh_token FROM gmail_connections WHERE owner_id=?').bind(owner).first<{encrypted_refresh_token:string}>();
  if(!gmail)throw new APIError(409,'GMAIL_REQUIRED','Connect Gmail before syncing bonds.');
  if(!env.GMAIL_CLIENT_ID || !env.GMAIL_CLIENT_SECRET)throw new APIError(503,'GMAIL_NOT_CONFIGURED','Gmail is not configured on the server.');
  const tokens=await gmailJSON(fetcher,'https://oauth2.googleapis.com/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({client_id:env.GMAIL_CLIENT_ID,client_secret:env.GMAIL_CLIENT_SECRET,refresh_token:await decrypt(gmail.encrypted_refresh_token,env.KITE_ENCRYPTION_KEY),grant_type:'refresh_token'})});
  if(typeof tokens.access_token!=='string' || !tokens.access_token)throw new Error('Missing Gmail token.');
  const headers={Authorization:'Bearer '+tokens.access_token};
  if(settings.scan_kind==='wint')return await syncWintBatch(env,owner,headers,settings.wint_cursor,lease,fetcher,at);
  const query=new URLSearchParams({q:'from:eCAS@cdslstatement.com subject:"CDSL Consolidated Account Statement" has:attachment filename:pdf newer_than:120d',maxResults:'10'});
  if(settings.scan_cursor)query.set('pageToken',settings.scan_cursor);
  let list;
  try { list=await gmailJSON(fetcher,'https://gmail.googleapis.com/gmail/v1/users/me/messages?'+query,{headers}); }
  catch(failure) {
   if(settings.scan_cursor)await env.DB.prepare('UPDATE bonds_settings SET scan_cursor=NULL WHERE owner_id=? AND lease_until=?').bind(owner,lease).run();
   throw failure;
  }
  if(!Array.isArray(list.messages) && list.messages!==undefined)throw new Error('Invalid mailbox response.');
  const messages=(list.messages??[]).slice(0,10);
  for(const message of messages) {
   if(typeof message.id!=='string' || !/^[a-zA-Z0-9_-]+$/.test(message.id))continue;
   const seen=await env.DB.prepare("SELECT status FROM bonds_imports WHERE owner_id=? AND message_id=? AND status IN ('imported','ignored')").bind(owner,message.id).first();
   if(seen)continue;
   const detail=await gmailJSON(fetcher,`https://gmail.googleapis.com/gmail/v1/users/me/messages/${message.id}?format=full`,{headers});
   if(!trustedBondMessage(detail.payload??{}))continue;
   const attachments=pdfs(detail.payload);
   if(attachments.length!==1)throw new Error('Expected one Bond statement PDF.');
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
   const duplicate=await env.DB.prepare('SELECT status FROM bonds_imports WHERE owner_id=? AND content_hash=?').bind(owner,hash).first<{status:string}>();
   if(duplicate && duplicate.status!=='needs_review')continue;
   try {
    const password=await decrypt(settings.encrypted_password,env.KITE_ENCRYPTION_KEY);
    const parsed=parseBondStatement(await extractStatementPDF(bytes,password),at);
    const status=await saveBondSnapshot(env,owner,parsed,message.id,hash,at,lease);
    return {imported:status==='imported'?1:0,status};
   }catch {
    await env.DB.prepare("INSERT INTO bonds_imports(owner_id,content_hash,message_id,status,error,imported_at) VALUES(?,?,?,'needs_review',?,?) ON CONFLICT(owner_id,content_hash) DO UPDATE SET error=excluded.error").bind(owner,hash,message.id,errorText,at.getTime()).run();
    throw new APIError(409,'BONDS_REVIEW_REQUIRED',errorText);
   }
  }
  const next=typeof list.nextPageToken==='string' && list.nextPageToken.length<=1024?list.nextPageToken:null;
  await env.DB.prepare('UPDATE bonds_settings SET scan_cursor=? WHERE owner_id=? AND lease_until=?').bind(next,owner,lease).run();
  if(next)return {imported:0,status:'scan_pending'};
  await env.DB.prepare("UPDATE bonds_settings SET scan_kind='wint' WHERE owner_id=? AND lease_until=?").bind(owner,lease).run();
  return await syncWintBatch(env,owner,headers,settings.wint_cursor,lease,fetcher,at);
 }catch(failure){
  error=failure instanceof APIError ? failure.message : 'Bond sync failed. Your previous bond balances are retained.';
  if(failure instanceof APIError && failure.code==='GMAIL_RECONNECT_REQUIRED')await env.DB.prepare("UPDATE gmail_connections SET status='reconnect',error=? WHERE owner_id=?").bind(error,owner).run();
  throw failure instanceof APIError ? failure : new APIError(502,'BONDS_SYNC_FAILED',error);
 }finally{await env.DB.prepare('UPDATE bonds_settings SET lease_until=0,last_sync_at=?,error=? WHERE owner_id=? AND lease_until=?').bind(at.getTime(),error,owner,lease).run();}
}

export function bondsRoutes(fetcher:typeof fetch=fetch,now=Date.now) {
 const app=new Hono<{Bindings:GmailEnvironment}>();
 app.onError((error,c)=>{const e=error instanceof APIError?error:new APIError(502,'BONDS_UNAVAILABLE','Bond sync failed. Your previous balances are retained.');return c.json({error:{code:e.code,message:e.message}},e.status);});
 app.use('*',async(c,next)=>{c.header('Cache-Control','no-store');await next();});
 app.get('/status',async c=>{
  const auth=await appSession(c.env,c.req.header('Authorization'),now);
  const settings=await c.env.DB.prepare('SELECT last_sync_at,error FROM bonds_settings WHERE owner_id=?').bind(auth.owner_id).first<{last_sync_at:number|null;error:string|null}>();
  const gmail=await c.env.DB.prepare("SELECT owner_id FROM gmail_connections WHERE owner_id=? AND status='connected'").bind(auth.owner_id).first();
  const result=await recordedBonds(c.env,auth.owner_id,new Date(now()));
  const exactTotal=result.holdings.reduce((sum,h)=>sum.plus(h.value??0),new Decimal(0)).toFixed();
  const matched=result.holdings.filter(h=>h.bondTerms?.investedAmount!==null).length;
  return c.json({configured:!!settings,gmailConnected:!!gmail,lastSyncAt:settings?.last_sync_at??null,error:settings?.error??null,balance:result.statementDate?{statement_date:result.statementDate,total:exactTotal,count:result.holdings.length,redemptionChecks:result.holdings.filter(h=>h.bondTerms?.redemptionCheck).length,matchedPurchases:matched}:null,redeemed:result.redeemed});
 });
 app.put('/password',async c=>{
  const auth=await appSession(c.env,c.req.header('Authorization'),now);
  const raw=await c.req.text();if(raw.length>512)throw new APIError(400,'INVALID_PASSWORD','Enter the first holder’s PAN.');
  let password:unknown;try{password=JSON.parse(raw).password;}catch{}
  if(typeof password!=='string' || !/^[A-Z]{5}[0-9]{4}[A-Z]$/.test(password.trim().toUpperCase()))throw new APIError(400,'INVALID_PASSWORD','Enter the first holder’s PAN.');
  await c.env.DB.prepare('INSERT INTO bonds_settings(owner_id,encrypted_password,updated_at) VALUES(?,?,?) ON CONFLICT(owner_id) DO UPDATE SET encrypted_password=excluded.encrypted_password,updated_at=excluded.updated_at,error=NULL,lease_until=0,scan_cursor=NULL').bind(auth.owner_id,await encrypt(password.trim().toUpperCase(),c.env.KITE_ENCRYPTION_KEY),now()).run();
  await c.env.DB.prepare("DELETE FROM bonds_imports WHERE owner_id=? AND status='needs_review'").bind(auth.owner_id).run();
  return c.json({saved:true});
 });
 app.delete('/connection',async c=>{
  const auth=await appSession(c.env,c.req.header('Authorization'),now);
  await c.env.DB.prepare('DELETE FROM bonds_settings WHERE owner_id=?').bind(auth.owner_id).run();return c.json({removed:true});
 });
 return app;
}
