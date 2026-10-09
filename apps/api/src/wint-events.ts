import {digest,type KiteEnvironment} from './zerodha';
import type {WintEvent,WintPurchase,WintPayout} from './wint-email';
export type StoredPurchase=Omit<WintPurchase,'accountID'>;
export type StoredEvent={accountHash:string|null;event:StoredPurchase|WintPayout};
type Env=Pick<KiteEnvironment,'DB'>;
export async function readWintEvents(env:Env,owner:string):Promise<StoredEvent[]> {
 const row=await env.DB.prepare("SELECT json_group_array(json_object('accountHash',account_hash,'event',json(data))) AS events FROM wint_events WHERE owner_id=?").bind(owner).first<{events:string}>();
 return JSON.parse(row?.events??'[]');
}
export async function saveWintEvent(env:Env,owner:string,event:WintEvent,message:string,at:Date,lease?:number) {
 let accountHash:string|null=null,data:StoredPurchase|WintPayout=event,economic:unknown=event;
 if(event.kind==='purchase') {
  const {accountID,...stored}=event;data=stored;accountHash=await digest(owner+':bonds:'+accountID);
  const {date,confirmed,name,...stable}=stored;economic={...stable,accountHash};
 }
 const hash=await digest(JSON.stringify(economic));
 const previous=await env.DB.prepare('SELECT economic_hash,data FROM wint_events WHERE owner_id=? AND event_key=?').bind(owner,event.key).first<{economic_hash:string;data:string}>();
 if(previous && previous.economic_hash!==hash)throw Error('Conflicting Wint event.');
 const old=previous?JSON.parse(previous.data) as StoredEvent['event']:null;
 const upgrade=old?.kind==='purchase' && !old.confirmed && event.kind==='purchase' && event.confirmed;
 if(previous && !upgrade) {
  const recorded=await env.DB.prepare("INSERT INTO wint_imports(owner_id,message_id,status,imported_at) SELECT ?,?,'imported',? WHERE (? IS NULL OR EXISTS(SELECT 1 FROM bonds_settings WHERE owner_id=? AND lease_until=?)) ON CONFLICT(owner_id,message_id) DO UPDATE SET status='imported',error=NULL RETURNING message_id").bind(owner,message,at.getTime(),lease??null,owner,lease??null).first();
  if(!recorded)throw Error('Bond settings changed during sync.');return 'duplicate';
 }
 const saved=await env.DB.prepare(`INSERT INTO wint_events(owner_id,event_key,account_hash,data,economic_hash,message_id,imported_at) SELECT ?,?,?,?,?,?,? WHERE (? IS NULL OR EXISTS(SELECT 1 FROM bonds_settings WHERE owner_id=? AND lease_until=?))
 ON CONFLICT(owner_id,event_key) DO UPDATE SET data=excluded.data,message_id=excluded.message_id,imported_at=excluded.imported_at WHERE wint_events.economic_hash=excluded.economic_hash AND json_extract(wint_events.data,'$.confirmed')=0 AND json_extract(excluded.data,'$.confirmed')=1 RETURNING event_key`).bind(owner,event.key,accountHash,JSON.stringify(data),hash,message,at.getTime(),lease??null,owner,lease??null).first();
 if(!saved)throw Error('Wint event superseded.');return 'imported';
}
