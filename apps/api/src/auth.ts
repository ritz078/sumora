import {Hono} from 'hono';
import {createRemoteJWKSet, customFetch, jwtVerify} from 'jose';
import {APIError,appSession,decrypt,digest,encrypt,randomToken,type KiteEnvironment} from './zerodha';
export interface AuthEnvironment extends KiteEnvironment {
 GOOGLE_CLIENT_ID?:string; GOOGLE_CLIENT_SECRET?:string; GOOGLE_REDIRECT_URI?:string;
 GMAIL_CLIENT_ID?:string; GMAIL_CLIENT_SECRET?:string;
}
interface Account {id:string;google_sub:string;email:string;data_owner_id:string;onboarding_completed:number}
interface Attempt {id:string;challenge:string;encrypted_verifier:string;nonce:string;expires_at:number;legacy_owner_id:string|null;identity:string}
export const googleLoginEnabled=(env:AuthEnvironment)=>!!env.GOOGLE_REDIRECT_URI;
const client=(env:AuthEnvironment)=>({id:env.GOOGLE_CLIENT_ID??env.GMAIL_CLIENT_ID,secret:env.GOOGLE_CLIENT_SECRET??env.GMAIL_CLIENT_SECRET});
const accountJSON=(a:Account)=>({id:a.id,email:a.email,onboardingCompleted:!!a.onboarding_completed});
async function body(request:Request) {
 const text=await request.text();if(text.length>2048)throw new APIError(400,'INVALID_REQUEST','Request is too large.');
 try{const value=JSON.parse(text);if(!value||typeof value!=='object'||Array.isArray(value))throw Error();return value as Record<string,unknown>;}catch{throw new APIError(400,'INVALID_REQUEST','Expected a JSON object.');}
}
export function authRoutes(fetcher:typeof fetch=fetch,now=Date.now) {
 const app=new Hono<{Bindings:AuthEnvironment}>();
 const keys=createRemoteJWKSet(new URL('https://www.googleapis.com/oauth2/v3/certs'),{[customFetch]:fetcher});
 app.use('*',async(c,next)=>{c.header('Cache-Control','no-store');c.header('Referrer-Policy','no-referrer');await next();});
 app.onError((error,c)=>{const e=error instanceof APIError?error:new APIError(502,'LOGIN_FAILED','Sign-in could not complete. Please try again.');return c.json({error:{code:e.code,message:e.message}},e.status);});
 function configured(env:AuthEnvironment) {
  const {id,secret}=client(env);let valid=false;
  try{const url=new URL(env.GOOGLE_REDIRECT_URI!);valid=url.protocol==='https:'&&url.pathname==='/v1/auth/google/callback'&&!url.search&&!url.hash;}catch{}
  if(!id||!secret||!valid||!env.KITE_ENCRYPTION_KEY)throw new APIError(503,'GOOGLE_NOT_CONFIGURED','Google sign-in is not configured yet.');
  return {id:id!,secret:secret!};
 }
 async function account(env:AuthEnvironment,authorization?:string) {
  const session=await appSession(env,authorization,now);
  const result=await env.DB.prepare('SELECT a.* FROM app_accounts a JOIN app_sessions s ON s.account_id=a.id WHERE s.token_hash=? AND s.expires_at>?').bind(session.token_hash,now()).first<Account>();
  if(!result)throw new APIError(401,'SIGN_IN_REQUIRED','Sign in with Google to continue.');return result;
 }
 app.post('/google/start',async c=>{
  const credentials=configured(c.env);const {challenge}=await body(c.req.raw);
  if(typeof challenge!=='string'||!/^[a-f0-9]{64}$/.test(challenge))throw new APIError(400,'INVALID_CHALLENGE','Invalid login challenge.');
  let legacy:string|null=null;
  if(c.req.header('Authorization')){
   const auth=await appSession(c.env,c.req.header('Authorization'),now);
   const migrated=await c.env.DB.prepare('SELECT id FROM app_accounts WHERE data_owner_id=?').bind(auth.owner_id).first();
   if(!migrated)legacy=auth.owner_id;
  }
  await c.env.DB.prepare('DELETE FROM google_login_attempts WHERE expires_at<=?').bind(now()).run();
  const count=await c.env.DB.prepare('SELECT count(*) AS n FROM google_login_attempts').first<{n:number}>();
  if((count?.n??0)>=50)throw new APIError(429,'LOGIN_BUSY','Too many login attempts. Try again shortly.');
  const state=randomToken(),verifier=randomToken(),nonce=randomToken();
  await c.env.DB.prepare('INSERT INTO google_login_attempts (id,challenge,encrypted_verifier,nonce,expires_at,legacy_owner_id) VALUES (?,?,?,?,?,?)').bind(state,challenge,await encrypt(verifier,c.env.KITE_ENCRYPTION_KEY),nonce,now()+600000,legacy).run();
  const challengeBytes=Uint8Array.from((await digest(verifier)).match(/../g)!,v=>parseInt(v,16));
  const googleChallenge=btoa(String.fromCharCode(...challengeBytes)).replaceAll('+','-').replaceAll('/','_').replaceAll('=','');
  const url=new URL('https://accounts.google.com/o/oauth2/v2/auth');
  url.search=new URLSearchParams({client_id:credentials.id,redirect_uri:c.env.GOOGLE_REDIRECT_URI!,response_type:'code',scope:'openid email profile',state,nonce,code_challenge:googleChallenge,code_challenge_method:'S256',prompt:'select_account'}).toString();
  return c.json({state,loginURL:url.toString()});
 });
 app.get('/google/callback',async c=>{
  const credentials=configured(c.env),state=c.req.query('state')??'';
  const redirect=new URL('sumora://login');redirect.searchParams.set('state',state);
  const fail=()=>{redirect.searchParams.set('error','LOGIN_FAILED');return c.redirect(redirect.toString());};
  // Atomically reserve the callback before exchanging its one-time Google code.
  const attempt=await c.env.DB.prepare('UPDATE google_login_attempts SET exchanging=1 WHERE id=? AND expires_at>? AND exchanging=0 RETURNING *').bind(state,now()).first<Attempt>();
  if(!attempt)return fail();
  try{
   const code=c.req.query('code');if(c.req.query('error')||!code||code.length>4096)throw Error();
   const response=await fetcher('https://oauth2.googleapis.com/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({client_id:credentials.id,client_secret:credentials.secret,redirect_uri:c.env.GOOGLE_REDIRECT_URI!,grant_type:'authorization_code',code,code_verifier:await decrypt(attempt.encrypted_verifier,c.env.KITE_ENCRYPTION_KEY)}),signal:AbortSignal.timeout(10000)});
   const tokens=await response.json() as {id_token?:string};if(!response.ok||typeof tokens.id_token!=='string')throw Error();
   const {payload}=await jwtVerify(tokens.id_token,keys,{issuer:['https://accounts.google.com','accounts.google.com'],audience:credentials.id,algorithms:['RS256'],currentDate:new Date(now()),requiredClaims:['sub','exp','iat','nonce','email']});
   if(payload.nonce!==attempt.nonce||payload.email_verified!==true||typeof payload.email!=='string'||!payload.email||typeof payload.sub!=='string'||!payload.sub||payload.sub.length>255||(payload.azp!==undefined&&payload.azp!==credentials.id))throw Error();
   const claim=randomToken();
   await c.env.DB.prepare('UPDATE google_login_attempts SET identity=?,result_hash=?,expires_at=? WHERE id=?').bind(JSON.stringify({sub:payload.sub,email:payload.email}),await digest(claim),now()+60000,state).run();
   redirect.searchParams.set('code',claim);return c.redirect(redirect.toString());
  }catch{await c.env.DB.prepare('DELETE FROM google_login_attempts WHERE id=?').bind(state).run();return fail();}
 });
 app.post('/google/claim',async c=>{
  configured(c.env);const {code,verifier}=await body(c.req.raw);
  if(typeof code!=='string'||!/^[a-f0-9]{64}$/.test(code)||typeof verifier!=='string'||!/^[a-zA-Z0-9_-]{43,128}$/.test(verifier))throw new APIError(401,'INVALID_LOGIN','Sign-in expired. Try again.');
  const attempt=await c.env.DB.prepare('DELETE FROM google_login_attempts WHERE result_hash=? AND challenge=? AND expires_at>? AND identity IS NOT NULL RETURNING *').bind(await digest(code),await digest(verifier),now()).first<Attempt>();
  if(!attempt)throw new APIError(401,'INVALID_LOGIN','Sign-in expired. Try again.');
  const identity=JSON.parse(attempt.identity) as {sub:string;email:string};
  let saved=await c.env.DB.prepare('SELECT * FROM app_accounts WHERE google_sub=?').bind(identity.sub).first<Account>();
  if(attempt.legacy_owner_id){
   const owner=await c.env.DB.prepare('SELECT * FROM app_accounts WHERE data_owner_id=?').bind(attempt.legacy_owner_id).first<Account>();
   if((owner&&owner.google_sub!==identity.sub)||(saved&&saved.data_owner_id!==attempt.legacy_owner_id))throw new APIError(409,'ACCOUNT_ALREADY_LINKED','This portfolio is already linked to an app account. Sign in to that account.');
  }
  const id=randomToken();
  await c.env.DB.prepare('INSERT INTO app_accounts (id,google_sub,email,data_owner_id,created_at) VALUES (?,?,?,?,?) ON CONFLICT(google_sub) DO NOTHING').bind(id,identity.sub,identity.email,attempt.legacy_owner_id??id,now()).run();
  saved=await c.env.DB.prepare('SELECT * FROM app_accounts WHERE google_sub=?').bind(identity.sub).first<Account>();
  if(!saved)throw Error();
  await c.env.DB.prepare('UPDATE app_accounts SET email=? WHERE id=?').bind(identity.email,saved.id).run();saved.email=identity.email;
  // Capture the broker credential before retiring legacy app sessions.
  await c.env.DB.prepare('INSERT INTO zerodha_connections (owner_id,client_id,encrypted_token,provider_expires_at) SELECT owner_id,owner_id,encrypted_token,provider_expires_at FROM zerodha_sessions WHERE owner_id=? ORDER BY provider_expires_at DESC LIMIT 1 ON CONFLICT(owner_id) DO UPDATE SET encrypted_token=excluded.encrypted_token,provider_expires_at=excluded.provider_expires_at WHERE excluded.provider_expires_at>=zerodha_connections.provider_expires_at').bind(saved.data_owner_id).run();
  await c.env.DB.prepare('DELETE FROM zerodha_sessions WHERE owner_id=?').bind(saved.data_owner_id).run();
  const token=randomToken();await c.env.DB.prepare('DELETE FROM app_sessions WHERE expires_at<=?').bind(now()).run();
  await c.env.DB.prepare('INSERT INTO app_sessions VALUES (?,?,?)').bind(await digest(token),saved.id,now()+30*86400000).run();
  return c.json({sessionToken:token,account:accountJSON(saved)});
 });
 app.get('/session',async c=>c.json({account:accountJSON(await account(c.env,c.req.header('Authorization')))}));
 app.delete('/session',async c=>{
  await account(c.env,c.req.header('Authorization'));
  await c.env.DB.prepare('DELETE FROM app_sessions WHERE token_hash=?').bind(await digest(c.req.header('Authorization')!.slice(7))).run();
  return c.json({loggedOut:true});
 });
 app.post('/onboarding',async c=>{
  const owner=await account(c.env,c.req.header('Authorization'));
  await c.env.DB.prepare('UPDATE app_accounts SET onboarding_completed=1 WHERE id=?').bind(owner.id).run();owner.onboarding_completed=1;
  return c.json({account:accountJSON(owner)});
 });
 return app;
}
