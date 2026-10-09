import { Hono } from 'hono';
import { APIError, appSession, digest, encrypt, decrypt, randomToken, type KiteEnvironment } from './zerodha';
export interface GmailEnvironment extends KiteEnvironment {
    GMAIL_CLIENT_ID?: string;
    GMAIL_CLIENT_SECRET?: string;
    GMAIL_REDIRECT_URI?: string;

}
const scope = 'https://www.googleapis.com/auth/gmail.readonly';
const tokenURL = 'https://oauth2.googleapis.com/token';

const timeout = () => AbortSignal.timeout(15000);
type GoogleTokens = {
    access_token?: string;
    refresh_token?: string;
    scope?: string;
};
type ConnectionStatus = Pick<Connection, 'email' | 'connected_at' | 'last_sync_at' | 'status' | 'error'>;
type Attempt = {
    id: string;
    owner_id: string;
    challenge: string;
    encrypted_verifier: string;
    expires_at: number;
    encrypted_refresh_token: string;
    email: string;
};
type Connection = {
    owner_id: string;
    email: string;
    encrypted_refresh_token: string;
    connected_at: number;
    last_sync_at: number | null;
    status: string;
    error: string | null;
    page_token: string | null;
    lease_id: string | null;
    sync_since: number;
};
export function gmailConfigured(env: GmailEnvironment) {
    if (!env.DB || !env.KITE_ENCRYPTION_KEY || !env.GMAIL_CLIENT_ID || !env.GMAIL_CLIENT_SECRET || !env.GMAIL_REDIRECT_URI) {
        throw new APIError(503, 'GMAIL_NOT_CONFIGURED', 'Gmail is not configured on the server yet.');
    }
    const redirect = new URL(env.GMAIL_REDIRECT_URI);
    if (redirect.protocol !== 'https:' || redirect.pathname !== '/v1/gmail/callback' || redirect.search || redirect.hash) {
        throw new APIError(503, 'GMAIL_NOT_CONFIGURED', 'Gmail callback configuration is invalid.');
    }
}
async function body(request: Request) {
    const text = await request.text();
    if (text.length > 2048)
        throw new APIError(400, 'INVALID_REQUEST', 'Request is too large.');
    try {
        const value = JSON.parse(text);
        if (!value || typeof value !== 'object' || Array.isArray(value))
            throw Error();
        return value as Record<string, unknown>;
    }
    catch {
        throw new APIError(400, 'INVALID_REQUEST', 'Expected a JSON object.');
    }
}
async function googleJSON<T>(fetcher: typeof fetch, url: string, init: RequestInit) {
    const response = await fetcher(url, { ...init, signal: timeout() });
    if (!response.ok) {
        const payload = await response.json().catch(() => ({})) as {
            error?: unknown;
        };
        if (response.status === 400 && url.includes('/messages?'))
            throw new APIError(502, 'GMAIL_PAGE_EXPIRED', 'Gmail search will restart on the next sync.');
        if (response.status === 401 || payload.error === 'invalid_grant')
            throw new APIError(409, 'GMAIL_RECONNECT_REQUIRED', 'Reconnect Gmail to continue collecting contract notes.');
        throw new APIError(502, 'GMAIL_UNAVAILABLE', 'Gmail could not be refreshed. Try again later.');
    }
    return response.json() as Promise<T>;
}
async function tokenRequest(env: GmailEnvironment, fetcher: typeof fetch, fields: Record<string, string>) {
    return googleJSON<GoogleTokens>(fetcher, tokenURL, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ client_id: env.GMAIL_CLIENT_ID!, client_secret: env.GMAIL_CLIENT_SECRET!, ...fields }) });
}
export function gmailRoutes(fetcher: typeof fetch = fetch, now = Date.now) {
    const app = new Hono<{
        Bindings: GmailEnvironment;
    }>();
    app.use('*', async (c, next) => { c.header('Cache-Control', 'no-store'); c.header('Referrer-Policy', 'no-referrer'); await next(); });
    app.onError((error, c) => {
        const failure = error instanceof APIError ? error : new APIError(502, 'GMAIL_UNAVAILABLE', 'Gmail is temporarily unavailable. Try again later.');
        return c.json({ error: { code: failure.code, message: failure.message } }, failure.status);
    });
    app.post('/start', async (c) => {
        const auth = await appSession(c.env, c.req.header('Authorization'), now);
        gmailConfigured(c.env);
        const { challenge } = await body(c.req.raw);
        if (typeof challenge !== 'string' || !/^[a-f0-9]{64}$/.test(challenge))
            throw new APIError(400, 'INVALID_CHALLENGE', 'Invalid login challenge.');
        await c.env.DB.prepare('DELETE FROM gmail_attempts WHERE expires_at <= ?').bind(now()).run();
        const count = await c.env.DB.prepare('SELECT count(*) AS total FROM gmail_attempts').first<{
            total: number;
        }>();
        if ((count?.total ?? 0) >= 50)
            throw new APIError(429, 'LOGIN_BUSY', 'Too many login attempts. Try again later.');
        const state = randomToken(), verifier = randomToken();
        const hash = await digest(verifier);
        const encoded = btoa(String.fromCharCode(...Uint8Array.from(hash.match(/../g)!, v => parseInt(v, 16)))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
        await c.env.DB.prepare('INSERT INTO gmail_attempts (id,owner_id,challenge,encrypted_verifier,expires_at) VALUES (?,?,?,?,?)')
            .bind(state, auth.owner_id, challenge, await encrypt(verifier, c.env.KITE_ENCRYPTION_KEY), now() + 600000).run();
        const url = new URL('https://accounts.google.com/o/oauth2/v2/auth');
        url.search = new URLSearchParams({ client_id: c.env.GMAIL_CLIENT_ID!, redirect_uri: c.env.GMAIL_REDIRECT_URI!, response_type: 'code', scope,
            access_type: 'offline', prompt: 'consent select_account', state, code_challenge: encoded, code_challenge_method: 'S256' }).toString();
        return c.json({ state, loginURL: url.toString() });
    });
    app.get('/callback', async (c) => {
        gmailConfigured(c.env);
        const state = c.req.query('state') ?? '';
        const redirect = new URL('sumora://gmail');
        redirect.searchParams.set('state', state);
        const attempt = await c.env.DB.prepare('SELECT * FROM gmail_attempts WHERE id = ? AND expires_at > ? AND result_hash IS NULL')
            .bind(state, now()).first<Attempt>();
        if (!attempt) {
            redirect.searchParams.set('error', 'LOGIN_EXPIRED');
            return c.redirect(redirect.toString());
        }
        const code = c.req.query('code');
        if (c.req.query('error') || !code || code.length > 2048) {
            await c.env.DB.prepare('DELETE FROM gmail_attempts WHERE id = ?').bind(state).run();
            redirect.searchParams.set('error', 'LOGIN_CANCELLED');
            return c.redirect(redirect.toString());
        }
        try {
            const tokens = await tokenRequest(c.env, fetcher, { grant_type: 'authorization_code', code, redirect_uri: c.env.GMAIL_REDIRECT_URI!, code_verifier: await decrypt(attempt.encrypted_verifier, c.env.KITE_ENCRYPTION_KEY) });
            if (typeof tokens.refresh_token !== 'string' || !tokens.refresh_token || typeof tokens.access_token !== 'string' || !tokens.access_token || typeof tokens.scope !== 'string' || !tokens.scope.split(' ').includes(scope))
                throw Error('Missing offline consent');
            const profile = await googleJSON<{
                emailAddress?: string;
            }>(fetcher, 'https://gmail.googleapis.com/gmail/v1/users/me/profile', { headers: { Authorization: 'Bearer ' + tokens.access_token } });
            if (typeof profile.emailAddress !== 'string' || !profile.emailAddress.includes('@') || profile.emailAddress.length > 254)
                throw Error('Invalid profile');
            const claim = randomToken();
            const updated = await c.env.DB.prepare('UPDATE gmail_attempts SET result_hash = ?, encrypted_refresh_token = ?, email = ?, expires_at = ? WHERE id = ? AND result_hash IS NULL AND expires_at > ? RETURNING id')
                .bind(await digest(claim), await encrypt(tokens.refresh_token, c.env.KITE_ENCRYPTION_KEY), profile.emailAddress, now() + 60000, state, now()).first();
            if (!updated)
                throw Error('Expired login');
            redirect.searchParams.set('code', claim);
        }
        catch {
            await c.env.DB.prepare('DELETE FROM gmail_attempts WHERE id = ?').bind(state).run();
            redirect.searchParams.set('error', 'LOGIN_FAILED');
        }
        return c.redirect(redirect.toString());
    });
    app.post('/claim', async (c) => {
        const auth = await appSession(c.env, c.req.header('Authorization'), now);
        gmailConfigured(c.env);
        const { code, verifier } = await body(c.req.raw);
        if (typeof code !== 'string' || !/^[a-f0-9]{64}$/.test(code) || typeof verifier !== 'string' || !/^[a-zA-Z0-9_-]{43,128}$/.test(verifier))
            throw new APIError(401, 'INVALID_LOGIN', 'Gmail login expired. Connect again.');
        const attempt = await c.env.DB.prepare('DELETE FROM gmail_attempts WHERE result_hash = ? AND challenge = ? AND owner_id = ? AND expires_at > ? AND encrypted_refresh_token IS NOT NULL RETURNING *')
            .bind(await digest(code), await digest(verifier), auth.owner_id, now()).first<Attempt>();
        if (!attempt)
            throw new APIError(401, 'INVALID_LOGIN', 'Gmail login expired. Connect again.');
        const previous = await c.env.DB.prepare('SELECT email FROM gmail_connections WHERE owner_id = ?').bind(auth.owner_id).first<{
            email: string;
        }>();
        if (previous && previous.email.toLowerCase() !== attempt.email.toLowerCase())
            throw new APIError(409, 'GMAIL_ACCOUNT_CHANGED', 'Disconnect the existing Gmail account before linking a different mailbox.');
        await c.env.DB.prepare("INSERT INTO gmail_connections (owner_id,email,encrypted_refresh_token,connected_at) VALUES (?,?,?,?) ON CONFLICT(owner_id) DO UPDATE SET encrypted_refresh_token=excluded.encrypted_refresh_token,status='connected',error=NULL,lease_id=NULL,lease_until=0")
            .bind(auth.owner_id, attempt.email, attempt.encrypted_refresh_token, now()).run();
        return c.json({ connected: true, email: attempt.email });
    });
    app.get('/connection', async (c) => {
        const auth = await appSession(c.env, c.req.header('Authorization'), now);
        const result = await c.env.DB.prepare('SELECT email,connected_at,last_sync_at,status,error FROM gmail_connections WHERE owner_id = ?').bind(auth.owner_id).first<ConnectionStatus>();
        return c.json({ connected: !!result, email: result?.email ?? null, status: result?.status ?? 'disconnected', lastSyncAt: result?.last_sync_at ?? null, error: result?.error ?? null });
    });
    app.delete('/connection', async (c) => {
        const auth = await appSession(c.env, c.req.header('Authorization'), now);
        const connection = await c.env.DB.prepare('DELETE FROM gmail_connections WHERE owner_id = ? RETURNING encrypted_refresh_token').bind(auth.owner_id).first<{
            encrypted_refresh_token: string;
        }>();
        await c.env.DB.prepare('DELETE FROM gmail_attempts WHERE owner_id = ?').bind(auth.owner_id).run();
        if (connection) {
            try {
                await fetcher('https://oauth2.googleapis.com/revoke', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ token: await decrypt(connection.encrypted_refresh_token, c.env.KITE_ENCRYPTION_KEY) }), signal: timeout() });
            }
            catch { /* Local unlink succeeds during Google outages. */ }
        }
        return c.json({ disconnected: true });
    });
    return app;
}
