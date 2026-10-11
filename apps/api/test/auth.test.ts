import {test} from 'node:test';
import assert from 'node:assert/strict';
import {app} from '../src/index';
import {setupGold} from './helpers/database';

test('Google login reports missing server configuration',async()=>{
 const {env}=setupGold();
 const result=await app.request('/v1/auth/google/start',{method:'POST',body:JSON.stringify({challenge:'a'.repeat(64)})},env);
 assert.equal(result.status,503);
});

import {Hono} from 'hono';
import {authRoutes} from '../src/auth';
import {zerodhaRoutes,appSession,digest,encrypt} from '../src/zerodha';
import {generateKeyPair,exportJWK,SignJWT} from 'jose';
const clock=()=>Date.UTC(2026,9,11,12);
async function fixture(overrides:Record<string,unknown>={}) {
 const {db,env:base}=setupGold();
 const env={...base,KITE_API_KEY:'kite-key',KITE_API_SECRET:'kite-secret',KITE_ENCRYPTION_KEY:btoa('a'.repeat(32)),GOOGLE_CLIENT_ID:'test-client',GOOGLE_CLIENT_SECRET:'secret',GOOGLE_REDIRECT_URI:'https://example.com/v1/auth/google/callback'};
 const {issuer='https://accounts.google.com',audience='test-client',expires=clock()/1000+300,badSignature=false,...claims}=overrides;
 const keys=await generateKeyPair('RS256'); const jwk={...await exportJWK(keys.publicKey),kid:'test',alg:'RS256'};
 let nonce='';
 const fetcher:typeof fetch=async(input,init)=>{
  if(String(input).includes('certs'))return Response.json({keys:[jwk]});
  assert.equal(String(input),'https://oauth2.googleapis.com/token');
  assert.ok(new URLSearchParams(String(init?.body)).get('code_verifier'));
  let id_token=await new SignJWT({email:'owner@example.com',email_verified:true,nonce,...claims}).setProtectedHeader({alg:'RS256',kid:'test'}).setIssuer(String(issuer)).setAudience(String(audience)).setSubject('google-owner').setIssuedAt(clock()/1000).setExpirationTime(Number(expires)).sign(keys.privateKey);
  if(badSignature){const pieces=id_token.split('.');pieces[2]=(pieces[2][0]==='a'?'b':'a')+pieces[2].slice(1);id_token=pieces.join('.');}
  return Response.json({id_token});
 };
 const broker:typeof fetch=async url=>String(url).endsWith('/session/token')?Response.json({status:'success',data:{user_id:'CLIENT',access_token:'kite-token'}}):Response.json({status:'success',data:[]});
 const app=new Hono().route('/v1/auth',authRoutes(fetcher,clock)).route('/v1/zerodha',zerodhaRoutes(broker,clock));
 const verifier='v'.repeat(64);
 async function login(legacy?:string) {
  const start=await app.request('/v1/auth/google/start',{method:'POST',headers:legacy?{Authorization:'Bearer '+legacy}:{},body:JSON.stringify({challenge:await digest(verifier)})},env);
  assert.equal(start.status,200);const data=await start.json();
  const url=new URL(data.loginURL);nonce=url.searchParams.get('nonce')!;
  assert.equal(url.searchParams.get('scope'),'openid email profile');
  const callback=await app.request('/v1/auth/google/callback?state='+data.state+'&code=google-code',{},env);
  const redirect=new URL(callback.headers.get('location')!);
  return {code:redirect.searchParams.get('code'),error:redirect.searchParams.get('error'),state:data.state};
 }
 async function claim(code:string|null,proof=verifier){return app.request('/v1/auth/google/claim',{method:'POST',body:JSON.stringify({code,verifier:proof})},env);}
 return {db,env,app,login,claim};
}
test('Google creates isolated app identity, single-use claim and persistent onboarding',async()=>{
 const f=await fixture(); const result=await f.login();assert.ok(result.code);
 assert.equal((await f.claim(result.code,'x'.repeat(64))).status,401);
 const claim=await f.claim(result.code);assert.equal(claim.status,200);const data=await claim.json();
 assert.equal(data.account.email,'owner@example.com');assert.equal(data.account.onboardingCompleted,false);
 assert.equal((await f.claim(result.code)).status,401);
 const headers={Authorization:'Bearer '+data.sessionToken};
 const session=await appSession(f.env,headers.Authorization,clock);assert.notEqual(session.owner_id,'google-owner');
 assert.equal((await f.app.request('/v1/auth/onboarding',{method:'POST',headers},f.env)).status,200);
 const next=await f.login(); const again=await (await f.claim(next.code)).json();
 assert.equal(again.account.id,data.account.id);assert.equal(again.account.onboardingCompleted,true);
});
test('Google refuses wrong nonce and unverified email',async()=>{
 for(const overrides of [{nonce:'wrong'},{email_verified:false},{issuer:'https://attacker.example'},{audience:'other-client'},{expires:clock()/1000-1},{badSignature:true}]) {
  const f=await fixture(overrides);const login=await f.login();assert.equal(login.code,null);assert.equal(login.error,'LOGIN_FAILED');
  assert.equal(f.db.prepare('SELECT count(*) AS n FROM app_accounts').get()!.n,0);
 }
});
test('legacy portfolio migration requires a valid session and logout retains provider credentials',async()=>{
 const f=await fixture();const token='a'.repeat(64);
 f.db.prepare('INSERT INTO zerodha_sessions VALUES (?,?,?,?,?)').run(await digest(token),await encrypt('broker-token',f.env.KITE_ENCRYPTION_KEY),'OWNER',clock()+10000,clock()+5000);
 f.db.prepare('INSERT INTO zerodha_connections VALUES (?,?,?,?)').run('OWNER','OWNER',await encrypt('old-token',f.env.KITE_ENCRYPTION_KEY),0);
 const login=await f.login(token);const claim=await (await f.claim(login.code)).json();
 const session=await appSession(f.env,'Bearer '+claim.sessionToken,clock);assert.equal(session.owner_id,'OWNER');
 assert.equal(f.db.prepare('SELECT provider_expires_at FROM zerodha_connections WHERE owner_id=?').get('OWNER')!.provider_expires_at,clock()+5000);
 assert.equal(f.db.prepare('SELECT count(*) AS n FROM zerodha_sessions').get()!.n,0);
 const result=await f.app.request('/v1/auth/session',{method:'DELETE',headers:{Authorization:'Bearer '+claim.sessionToken}},f.env);assert.equal(result.status,200);
 await assert.rejects(appSession(f.env,'Bearer '+claim.sessionToken,clock));
 assert.equal(f.db.prepare('SELECT count(*) AS n FROM zerodha_connections').get()!.n,1);
 const next=await f.login();const again=await (await f.claim(next.code)).json();
 assert.equal((await appSession(f.env,'Bearer '+again.sessionToken,clock)).owner_id,'OWNER');
});
test('invalid legacy proof cannot link holdings',async()=>{
 const f=await fixture();const response=await f.app.request('/v1/auth/google/start',{method:'POST',headers:{Authorization:'Bearer '+'b'.repeat(64)},body:JSON.stringify({challenge:'a'.repeat(64)})},f.env);assert.equal(response.status,401);
});

test('Google account can load holdings before connecting Zerodha and disconnect without logout',async()=>{
 const f=await fixture();const login=await f.login();const {sessionToken}=await (await f.claim(login.code)).json();const headers={Authorization:'Bearer '+sessionToken};
 const portfolio=await f.app.request('/v1/zerodha/portfolio',{headers},f.env);assert.equal(portfolio.status,200);assert.equal((await portfolio.json()).value,'0');
 assert.equal((await f.app.request('/v1/zerodha/start',{method:'POST',body:JSON.stringify({challenge:'a'.repeat(64)})},f.env)).status,401);
 const verifier='v'.repeat(64);const start=await f.app.request('/v1/zerodha/start',{method:'POST',headers,body:JSON.stringify({challenge:await digest(verifier)})},f.env);assert.equal(start.status,200);
 const {state}=await start.json();const callback=await f.app.request('/v1/zerodha/callback?state='+state+'&status=success&request_token=token',{},f.env);const code=new URL(callback.headers.get('location')!).searchParams.get('code');
 assert.equal((await f.app.request('/v1/zerodha/claim',{method:'POST',body:JSON.stringify({code,verifier})},f.env)).status,401);
 const connected=await f.app.request('/v1/zerodha/claim',{method:'POST',headers,body:JSON.stringify({code,verifier})},f.env);assert.equal(connected.status,200);assert.equal((await connected.json()).connected,true);
 assert.equal((await f.app.request('/v1/zerodha/connection',{method:'DELETE',headers},f.env)).status,200);
 assert.equal((await f.app.request('/v1/auth/session',{headers},f.env)).status,200);
 assert.equal(f.db.prepare('SELECT count(*) AS n FROM zerodha_connections').get()!.n,0);
});

test('matching email alone cannot claim another account portfolio',async()=>{
 const f=await fixture();
 f.db.prepare('INSERT INTO app_accounts VALUES (?,?,?,?,?,?)').run('other-account','different-google-sub','owner@example.com','private-owner',1,clock());
 const login=await f.login();const claim=await (await f.claim(login.code)).json();
 assert.notEqual(claim.account.id,'other-account');
 const auth=await appSession(f.env,'Bearer '+claim.sessionToken,clock);assert.notEqual(auth.owner_id,'private-owner');
});
test('Google callback cannot be exchanged twice but the first claim remains valid',async()=>{
 const f=await fixture();const login=await f.login();
 const replay=await f.app.request('/v1/auth/google/callback?state='+login.state+'&code=replay',{},f.env);
 assert.equal(new URL(replay.headers.get('location')!).searchParams.get('error'),'LOGIN_FAILED');
 assert.equal((await f.claim(login.code)).status,200);
});
