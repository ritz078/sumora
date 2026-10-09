import {syncBonds} from './bonds';
import {syncNPS} from './nps';
import {syncGullak} from './gullak';
import {syncHDFC} from './hdfc';
import type {GmailEnvironment} from './gmail';
// One mailbox source per invocation keeps statement and price jobs within the free query budget.
export async function scheduledStatements(env:GmailEnvironment,fetcher:typeof fetch=fetch,at=new Date()) {
    const next = await env.DB.prepare(`SELECT owner_id,kind FROM (
      SELECT s.owner_id,'gullak' AS kind,COALESCE(s.last_sync_at,0) AS attempted FROM gullak_settings s JOIN gmail_connections g ON s.owner_id=g.owner_id WHERE g.status='connected'
      UNION ALL SELECT s.owner_id,'hdfc' AS kind,COALESCE(s.last_sync_at,0) AS attempted FROM hdfc_settings s JOIN gmail_connections g ON s.owner_id=g.owner_id WHERE g.status='connected'
      UNION ALL SELECT s.owner_id,'nps' AS kind,COALESCE(s.last_sync_at,0) AS attempted FROM nps_settings s JOIN gmail_connections g ON s.owner_id=g.owner_id WHERE g.status='connected'
      UNION ALL SELECT s.owner_id,'bonds' AS kind,COALESCE(s.last_sync_at,0) AS attempted FROM bonds_settings s JOIN gmail_connections g ON s.owner_id=g.owner_id WHERE g.status='connected'
    ) ORDER BY attempted LIMIT 1`).first<{owner_id:string;kind:string}>();
    if(next)try { await (next.kind==='bonds'?syncBonds:next.kind==='nps'?syncNPS:next.kind==='hdfc'?syncHDFC:syncGullak)(env,next.owner_id,fetcher,at); }catch { /* Account sync error is persisted without blocking price refresh. */ }
}
