import {test} from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {readFileSync} from 'node:fs';
import { app } from '../src/index';
import {gmailRoutes} from '../src/gmail';
import {digest,decrypt} from '../src/zerodha';
async function setup(){
 const db=new DatabaseSync(':memory:');
 for(const name of ['0001_zerodha','0002_gmail'])db.exec(readFileSync(new URL('../migrations/'+name+'.sql',import.meta.url),'utf8'));
 const token='a'.repeat(64),key=Buffer.alloc(32,1).toString('base64');
 db.prepare('INSERT INTO zerodha_sessions VALUES (?,?,?,?,?)').run(await digest(token),'unused','DEMO01',Date.now()+86400000,0);
 const env:any={KITE_ENCRYPTION_KEY:key,GMAIL_CLIENT_ID:'test-client',GMAIL_CLIENT_SECRET:'test-secret',GMAIL_REDIRECT_URI:'https://example.com/v1/gmail/callback',DB:{prepare(sql:string){let args:any[]=[];return {bind(...values:any[]){args=values;return this;},async first(){return db.prepare(sql).get(...args)??null;},async run(){return db.prepare(sql).run(...args);}};}}};
 const routes=gmailRoutes(async(url)=>String(url).includes('/token')?Response.json({access_token:'access',refresh_token:'refresh-private',scope:'https://www.googleapis.com/auth/gmail.readonly'}):Response.json({emailAddress:'owner@example.com'}));
 const request=(path:string,method='GET',body?:unknown,authorized=true)=>routes.request(path,{method,headers:{'Content-Type':'application/json',...(authorized?{Authorization:'Bearer '+token}:{})},body:body?JSON.stringify(body):undefined},env);
 return {db,env,request,token};
}
test('Gmail linking remains mounted while contract-note operations are retired',async()=>{
 const c=await setup();
 assert.equal((await app.request('/v1/gmail/connection',{headers:{Authorization:'Bearer '+c.token}},c.env)).status,200);
 assert.equal((await c.request('/connection','GET',undefined,false)).status,401);
 assert.equal((await c.request('/sync','POST')).status,404);
 assert.equal((await c.request('/decryption','PUT',{pan:'ABCDE1234F'})).status,404);
});
test('read-only Gmail OAuth retains encrypted credentials and verifier-bound single-use claims',async()=>{
 const c=await setup(),verifier='b'.repeat(64);
 const start=await (await c.request('/start','POST',{challenge:await digest(verifier)})).json();
 const url=new URL(start.loginURL);assert.equal(url.searchParams.get('scope'),'https://www.googleapis.com/auth/gmail.readonly');assert.equal(url.searchParams.get('access_type'),'offline');
 const callback=await c.request('/callback?state='+start.state+'&code=google-code');
 const code=new URL(callback.headers.get('location')!).searchParams.get('code');assert.ok(code);
 assert.equal((await c.request('/claim','POST',{code,verifier:'c'.repeat(64)})).status,401);
 assert.equal((await c.request('/claim','POST',{code,verifier})).status,200);
 assert.equal((await c.request('/claim','POST',{code,verifier})).status,401);
 const stored=c.db.prepare('SELECT encrypted_refresh_token FROM gmail_connections').get()!;
 assert.equal(await decrypt(String(stored.encrypted_refresh_token),c.env.KITE_ENCRYPTION_KEY),'refresh-private');
 const status=await (await c.request('/connection')).text();assert.ok(!status.includes('refresh-private'));assert.equal(JSON.parse(status).email,'owner@example.com');
});
