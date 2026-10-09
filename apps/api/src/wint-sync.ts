import type {GmailEnvironment} from './gmail';
import {APIError} from './zerodha';
import {gmailJSON} from './statement-mailbox';
import {trustedWintMessage,gmailBody,parseWintEmail} from './wint-email';
import {saveWintEvent} from './wint-events';
export async function syncWintBatch(env:GmailEnvironment,owner:string,headers:Record<string,string>,cursor:string|null,lease:number,fetcher:typeof fetch,at:Date) {
 const query=new URLSearchParams({q:'{from:transactions@wintwealth.com from:receipts@wintwealth.com} {subject:"Investment Successful" subject:"order receipt" subject:"Just Credited" subject:"Asset Matured"}',maxResults:'5'});
 if(cursor)query.set('pageToken',cursor);
 let list;
 try {list=await gmailJSON(fetcher,'https://gmail.googleapis.com/gmail/v1/users/me/messages?'+query,{headers});}
 catch(error){await env.DB.prepare('UPDATE bonds_settings SET wint_cursor=NULL WHERE owner_id=? AND lease_until=?').bind(owner,lease).run();throw error;}
 if(!Array.isArray(list.messages) && list.messages!==undefined)throw Error('Invalid Wint mailbox response.');
 let imported=0,review=false;
 for(const message of (list.messages??[]).slice(0,5)) {
  if(typeof message.id!=='string' || !/^[a-zA-Z0-9_-]+$/.test(message.id))continue;
  if(await env.DB.prepare("SELECT message_id FROM wint_imports WHERE owner_id=? AND message_id=? AND status IN ('imported','ignored')").bind(owner,message.id).first())continue;
  const detail=await gmailJSON(fetcher,`https://gmail.googleapis.com/gmail/v1/users/me/messages/${message.id}?format=full`,{headers});
  if(!trustedWintMessage(detail.payload??{}))continue;
  try {
   const subject=detail.payload.headers.find((h:{name:string})=>h.name.toLowerCase()==='subject').value;
   const parsed=parseWintEmail(subject,gmailBody(detail.payload),at);
   if(await saveWintEvent(env,owner,parsed,message.id,at,lease)==='imported')imported++;
  }catch {
   review=true;
   await env.DB.prepare("INSERT INTO wint_imports(owner_id,message_id,status,error,imported_at) SELECT ?,?,'needs_review',?,? WHERE EXISTS(SELECT 1 FROM bonds_settings WHERE owner_id=? AND lease_until=?) ON CONFLICT(owner_id,message_id) DO UPDATE SET status='needs_review',error=excluded.error").bind(owner,message.id,'Wint email needs review. Existing bond data is retained.',at.getTime(),owner,lease).run();
  }
 }
 const next=typeof list.nextPageToken==='string' && list.nextPageToken.length<=1024?list.nextPageToken:null;
 await env.DB.prepare('UPDATE bonds_settings SET wint_cursor=?,scan_kind=? WHERE owner_id=? AND lease_until=?').bind(next,next?'wint':'cas',owner,lease).run();
 if(review)throw new APIError(409,'WINT_REVIEW_REQUIRED','A Wint email needs review. Other valid emails were imported; failed emails retain their previous data.');
 return {imported,status:next?'scan_pending':'up_to_date'};
}
