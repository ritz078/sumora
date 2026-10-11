import { Hono } from 'hono';
import { zerodhaSnapshot } from './zerodha-portfolio';
import type { Portfolio } from './portfolio-valuation';
import { valuedSnapshot } from './daily-valuation-job';

export interface Statement {
  bind(...values: unknown[]): Statement;
  first<T>(): Promise<T | null>;
  run(): Promise<unknown>;
}
export interface KiteEnvironment {
  DB: { prepare(sql: string): Statement };
  GOOGLE_REDIRECT_URI?: string;
  KITE_API_KEY: string;
  KITE_API_SECRET: string;
  KITE_ENCRYPTION_KEY: string;
}
type Attempt = { app_owner_id?: string; id: string; challenge: string; expires_at: number; encrypted_token: string; provider_expires_at: number; owner_id: string };
type Session = { token_hash: string; encrypted_token: string; provider_expires_at: number; owner_id: string; expires_at: number };
type Snapshot = Portfolio;
export class APIError extends Error {
  constructor(readonly status: 400 | 401 | 403 | 404 | 409 | 429 | 500 | 502 | 503, readonly code: string, message: string) { super(message); }
}
export async function digest(text: string) {
  const bytes = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return Array.from(new Uint8Array(bytes), (v) => v.toString(16).padStart(2, '0')).join('');
}
export const randomToken = () => Array.from(crypto.getRandomValues(new Uint8Array(32)), (v) => v.toString(16).padStart(2, '0')).join('');
const base64 = (bytes: Uint8Array) => {
  let text = '';
  for (let i = 0; i < bytes.length; i += 8192) text += String.fromCharCode(...bytes.subarray(i, i + 8192));
  return btoa(text);
};
const unbase64 = (text: string) => Uint8Array.from(atob(text), (v) => v.charCodeAt(0));
async function key(secret: string) {
  return crypto.subtle.importKey('raw', unbase64(secret), 'AES-GCM', false, ['encrypt', 'decrypt']);
}
export async function encrypt(token: string, secret: string) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const encrypted = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, await key(secret), new TextEncoder().encode(token));
  return `${base64(iv)}.${base64(new Uint8Array(encrypted))}`;
}
export async function decrypt(token: string, secret: string) {
  const [iv, value] = token.split('.');
  const decrypted = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: unbase64(iv) }, await key(secret), unbase64(value));
  return new TextDecoder().decode(decrypted);
}
async function jsonBody(request: Request): Promise<Record<string, unknown>> {
  const text = await request.text();
  if (text.length > 2048) throw new APIError(400, 'INVALID_REQUEST', 'Request is too large.');
  try {
    const result = JSON.parse(text);
    if (!result || typeof result !== 'object' || Array.isArray(result)) throw new Error();
    return result;
  } catch { throw new APIError(400, 'INVALID_REQUEST', 'Expected a JSON object.'); }
}
export async function appSession(env: Pick<KiteEnvironment, 'DB' | 'GOOGLE_REDIRECT_URI'>, authorization: string | undefined, now = Date.now) {
  if (!authorization?.match(/^Bearer [a-f0-9]{64}$/)) throw new APIError(401, 'SIGN_IN_REQUIRED', 'Sign in to Sumora to continue.');
  const hash=await digest(authorization.slice(7));
  // Transitional compatibility is used only by deployments without Google login configured.
  if(env.GOOGLE_REDIRECT_URI) {
    const result=await env.DB.prepare('SELECT s.token_hash,s.expires_at,a.data_owner_id AS owner_id FROM app_sessions s JOIN app_accounts a ON a.id=s.account_id WHERE s.token_hash=? AND s.expires_at>?').bind(hash,now()).first<Session>();
    if(result?.owner_id)return result;
  }
  const result = await env.DB.prepare('SELECT * FROM zerodha_sessions WHERE token_hash = ? AND expires_at > ?')
    .bind(hash, now()).first<Session>();
  if (!result?.owner_id) throw new APIError(401, 'SIGN_IN_REQUIRED', 'Sign in to Sumora to continue.');
  return result;
}
export function zerodhaRoutes(fetcher: typeof fetch = fetch, now = Date.now) {
  const app = new Hono<{ Bindings: KiteEnvironment }>();
  app.use('*', async (c, next) => {
    c.header('Cache-Control', 'no-store');
    c.header('Referrer-Policy', 'no-referrer');
    await next();
  });
  app.onError((error, c) => {
    const failure = error instanceof APIError ? error : new APIError(502, 'ZERODHA_UNAVAILABLE', 'Zerodha could not be refreshed. Try again later.');
    return c.json({ error: { code: failure.code, message: failure.message } }, failure.status);
  });
  function configured(env: KiteEnvironment) {
    if (!env?.DB || !env.KITE_API_KEY || !env.KITE_API_SECRET || !env.KITE_ENCRYPTION_KEY) {
      throw new APIError(503, 'ZERODHA_NOT_CONFIGURED', 'The Zerodha connection is not configured on the server yet.');
    }
  }
  async function session(env: KiteEnvironment, authorization?: string): Promise<Session> {
    const auth=await appSession(env,authorization,now);
    if(!env.GOOGLE_REDIRECT_URI)return auth;
    const connection=await env.DB.prepare('SELECT * FROM zerodha_connections WHERE owner_id=?').bind(auth.owner_id).first<{encrypted_token:string;provider_expires_at:number}>();
    return {...auth,encrypted_token:connection?.encrypted_token??'',provider_expires_at:connection?.provider_expires_at??0};
  }
  async function kite(env: KiteEnvironment, path: string, token: string, method = 'GET') {
    const url = new URL(`https://api.kite.trade${path}`);
    if (method === 'DELETE' && path === '/session/token') {
      url.search = new URLSearchParams({ api_key: env.KITE_API_KEY, access_token: token }).toString();
    }
    const response = await fetcher(url.toString(), { method, headers: {
      'X-Kite-Version': '3', Authorization: `token ${env.KITE_API_KEY}:${token}`,
    }, signal: AbortSignal.timeout(10000) });
    if (response.status === 401 || response.status === 403) throw new APIError(409, 'ZERODHA_RECONNECT_REQUIRED', 'Your Kite session expired. Reconnect Zerodha.');
    if (!response.ok) throw new APIError(502, 'ZERODHA_UNAVAILABLE', 'Zerodha could not be refreshed. Try again later.');
    return response.text();
  }
  app.post('/start', async (c) => {
    configured(c.env);
    const owner=c.env.GOOGLE_REDIRECT_URI?(await appSession(c.env,c.req.header('Authorization'),now)).owner_id:null;
    const { challenge } = await jsonBody(c.req.raw);
    if (typeof challenge !== 'string' || !/^[a-f0-9]{64}$/.test(challenge)) throw new APIError(400, 'INVALID_CHALLENGE', 'Invalid login challenge.');
    await c.env.DB.prepare('DELETE FROM zerodha_attempts WHERE expires_at <= ?').bind(now()).run();
    await c.env.DB.prepare('DELETE FROM zerodha_sessions WHERE expires_at <= ?').bind(now()).run();
    const count = await c.env.DB.prepare('SELECT count(*) AS total FROM zerodha_attempts').first<{ total: number }>();
    if ((count?.total ?? 0) >= 50) throw new APIError(429, 'LOGIN_BUSY', 'Too many login attempts. Try again in a few minutes.');
    const state = randomToken();
    if(c.env.GOOGLE_REDIRECT_URI)await c.env.DB.prepare('INSERT INTO zerodha_attempts (id,challenge,expires_at,app_owner_id) VALUES (?,?,?,?)').bind(state,challenge,now()+600000,owner).run();
    else await c.env.DB.prepare('INSERT INTO zerodha_attempts (id, challenge, expires_at) VALUES (?, ?, ?)').bind(state, challenge, now() + 600000).run();
    const url = new URL('https://kite.zerodha.com/connect/login');
    url.search = new URLSearchParams({ v: '3', api_key: c.env.KITE_API_KEY, redirect_params: new URLSearchParams({ state }).toString() }).toString();
    return c.json({ state, loginURL: url.toString() });
  });
  app.get('/callback', async (c) => {
    configured(c.env);
    const state = c.req.query('state') ?? '';
    const redirect = new URL('sumora://zerodha');
    redirect.searchParams.set('state', state);
    const attempt = await c.env.DB.prepare('SELECT * FROM zerodha_attempts WHERE id = ? AND expires_at > ? AND encrypted_token IS NULL').bind(state, now()).first<Attempt>();
    if (!attempt) { redirect.searchParams.set('error', 'LOGIN_EXPIRED'); return c.redirect(redirect.toString()); }
    const requestToken = c.req.query('request_token');
    if (c.req.query('status') !== 'success' || !requestToken || requestToken.length > 512) {
      await c.env.DB.prepare('DELETE FROM zerodha_attempts WHERE id = ?').bind(state).run();
      redirect.searchParams.set('error', 'LOGIN_CANCELLED'); return c.redirect(redirect.toString());
    }
    const body = new URLSearchParams({ api_key: c.env.KITE_API_KEY, request_token: requestToken,
      checksum: await digest(c.env.KITE_API_KEY + requestToken + c.env.KITE_API_SECRET) });
    const response = await fetcher('https://api.kite.trade/session/token', {
      method: 'POST', headers: { 'X-Kite-Version': '3', 'Content-Type': 'application/x-www-form-urlencoded' }, body,
      signal: AbortSignal.timeout(10000),
    });
    const result = await response.json() as { status: string; data?: { user_id: string; access_token: string } };
    if (!response.ok || result.status !== 'success' || typeof result.data?.access_token !== 'string' || !result.data.access_token || typeof result.data.user_id !== 'string' || !/^[a-zA-Z0-9]{1,32}$/.test(result.data.user_id)) {
      redirect.searchParams.set('error', 'LOGIN_FAILED'); return c.redirect(redirect.toString());
    }
    const code = randomToken();
    const ist = new Date(now() + 330 * 60000);
    let providerExpiry = Date.UTC(ist.getUTCFullYear(), ist.getUTCMonth(), ist.getUTCDate(), 6) - 330 * 60000;
    if (providerExpiry <= now()) providerExpiry += 86400000;
    const updated = await c.env.DB.prepare('UPDATE zerodha_attempts SET result_hash = ?, encrypted_token = ?, owner_id = ?, provider_expires_at = ?, expires_at = ? WHERE id = ? AND encrypted_token IS NULL AND expires_at > ? RETURNING id')
      .bind(await digest(code), await encrypt(result.data.access_token, c.env.KITE_ENCRYPTION_KEY), result.data.user_id, providerExpiry, now() + 60000, state, now()).first<{ id: string }>();
    if (!updated) { redirect.searchParams.set('error', 'LOGIN_EXPIRED'); return c.redirect(redirect.toString()); }
    redirect.searchParams.set('code', code);
    return c.redirect(redirect.toString());
  });
  app.post('/claim', async (c) => {
    configured(c.env);
    const owner=c.env.GOOGLE_REDIRECT_URI?(await appSession(c.env,c.req.header('Authorization'),now)).owner_id:null;
    const { code, verifier } = await jsonBody(c.req.raw);
    if (typeof code !== 'string' || !/^[a-f0-9]{64}$/.test(code) || typeof verifier !== 'string' || !/^[a-zA-Z0-9_-]{43,128}$/.test(verifier)) {
      throw new APIError(401, 'INVALID_LOGIN', 'Login expired. Try connecting again.');
    }
    const sql='DELETE FROM zerodha_attempts WHERE result_hash=? AND challenge=? AND expires_at>? AND encrypted_token IS NOT NULL'+(owner?' AND app_owner_id=?':'')+' RETURNING *';
    const statement=c.env.DB.prepare(sql);
    const values=[await digest(code),await digest(verifier),now()];
    const attempt=await statement.bind(...values,...(owner?[owner]:[])).first<Attempt>();
    if (!attempt || !attempt.owner_id) throw new APIError(401, 'INVALID_LOGIN', 'Login expired. Try connecting again.');
    if(owner){
      const existing=await c.env.DB.prepare('SELECT owner_id FROM zerodha_connections WHERE client_id=?').bind(attempt.owner_id).first<{owner_id:string}>();
      if(existing&&existing.owner_id!==owner)throw new APIError(409,'ACCOUNT_ALREADY_LINKED','This Zerodha account is already linked to another app account.');
      const current=await c.env.DB.prepare('SELECT client_id FROM zerodha_connections WHERE owner_id=?').bind(owner).first<{client_id:string}>();
      if(current&&current.client_id!==attempt.owner_id)throw new APIError(409,'ACCOUNT_SWITCH_REQUIRES_DISCONNECT','Disconnect the current Zerodha account before switching accounts.');
      await c.env.DB.prepare('INSERT INTO zerodha_connections VALUES (?,?,?,?) ON CONFLICT(owner_id) DO UPDATE SET encrypted_token=excluded.encrypted_token,provider_expires_at=excluded.provider_expires_at').bind(owner,attempt.owner_id,attempt.encrypted_token,attempt.provider_expires_at).run();
      return c.json({connected:true,userID:attempt.owner_id});
    }
    const token = randomToken();
    await c.env.DB.prepare('INSERT INTO zerodha_sessions (token_hash, encrypted_token, owner_id, expires_at, provider_expires_at) VALUES (?, ?, ?, ?, ?)')
      .bind(await digest(token), attempt.encrypted_token, attempt.owner_id, now() + 30 * 86400000, attempt.provider_expires_at).run();
    return c.json({ sessionToken: token, userID: attempt.owner_id });
  });
  app.get('/portfolio', async (c) => {
    const auth = await session(c.env, c.req.header('Authorization'));
    const cached = await c.env.DB.prepare('SELECT * FROM zerodha_snapshots WHERE owner_id = ?').bind(auth.owner_id).first<{ snapshot: string; synced_at: number }>();
    const stale = async () => {
      if(!cached&&c.env.GOOGLE_REDIRECT_URI){
        const snapshot=zerodhaSnapshot('{"status":"success","data":[]}','{"status":"success","data":[]}',new Date(now())) as Snapshot;
        snapshot.connections[0].status=auth.encrypted_token?'attention':'disconnected';
        snapshot.connections[0].lastSyncAt=null;
        snapshot.connections[0].description=auth.encrypted_token?'Reconnect Zerodha to import holdings.':'Connect Zerodha to import Indian stocks and mutual funds.';
        return c.json(await valuedSnapshot(c.env,snapshot,new Date(now()),auth.owner_id));
      }
      if (!cached) throw new APIError(409, 'ZERODHA_RECONNECT_REQUIRED', 'Your Kite session expired. Reconnect Zerodha.');
      const snapshot = JSON.parse(cached.snapshot) as Snapshot;
      snapshot.connections[0].status = 'attention';
      snapshot.connections[0].description = 'Kite session expired. Reconnect to update quantities. Available independent closing prices are applied to recorded holdings.';
      return c.json(await valuedSnapshot(c.env, snapshot, new Date(now()), auth.owner_id));
    };
    if (auth.provider_expires_at <= now()) return stale();
    if (cached && cached.synced_at > now() - 30000) return c.json(await valuedSnapshot(c.env, JSON.parse(cached.snapshot) as Snapshot, new Date(now()), auth.owner_id));
    try {
      const token = await decrypt(auth.encrypted_token, c.env.KITE_ENCRYPTION_KEY);
      const [equity, funds] = await Promise.all([kite(c.env, '/portfolio/holdings', token), kite(c.env, '/mf/holdings', token)]);
      let snapshot: Snapshot;
      try { snapshot = zerodhaSnapshot(equity, funds, new Date(now())); }
      catch (error) { throw new APIError(502, 'HOLDINGS_IMPORT_FAILED', error instanceof Error ? error.message : 'Unable to import holdings.'); }
      await c.env.DB.prepare('INSERT INTO zerodha_snapshots (owner_id, snapshot, synced_at) VALUES (?, ?, ?) ON CONFLICT(owner_id) DO UPDATE SET snapshot = excluded.snapshot, synced_at = excluded.synced_at')
        .bind(auth.owner_id, JSON.stringify(snapshot), now()).run();
      return c.json(await valuedSnapshot(c.env, snapshot, new Date(now()), auth.owner_id));
    } catch (error) {
      if (error instanceof APIError && error.code === 'ZERODHA_RECONNECT_REQUIRED') {
        if(c.env.GOOGLE_REDIRECT_URI)await c.env.DB.prepare('UPDATE zerodha_connections SET provider_expires_at=0 WHERE owner_id=?').bind(auth.owner_id).run();
        else await c.env.DB.prepare('UPDATE zerodha_sessions SET provider_expires_at = 0 WHERE token_hash = ?').bind(auth.token_hash).run();
        return stale();
      }
      throw error;
    }
  });
  app.get('/connection',async c=>{
    const auth=await session(c.env,c.req.header('Authorization'));
    return c.json({connected:!!auth.encrypted_token,status:!auth.encrypted_token?'disconnected':auth.provider_expires_at<=now()?'reconnect':'connected'});
  });
  app.delete('/connection', async (c) => {
    const auth = await session(c.env, c.req.header('Authorization'));
    try { await kite(c.env, '/session/token', await decrypt(auth.encrypted_token, c.env.KITE_ENCRYPTION_KEY), 'DELETE'); } catch { /* Local access is removed even if Kite is unavailable. */ }
    if(c.env.GOOGLE_REDIRECT_URI)await c.env.DB.prepare('DELETE FROM zerodha_connections WHERE owner_id=?').bind(auth.owner_id).run();
    else await c.env.DB.prepare('DELETE FROM zerodha_sessions WHERE owner_id = ?').bind(auth.owner_id).run();
    await c.env.DB.prepare('DELETE FROM zerodha_snapshots WHERE owner_id = ?').bind(auth.owner_id).run();
    return c.json({ disconnected: true });
  });
  return app;
}
