import {DatabaseSync} from 'node:sqlite';
import {readFileSync} from 'node:fs';
export function setupGold() {
 const db = new DatabaseSync(':memory:');
 for (const name of ['0001_zerodha','0002_gmail','0007_daily_prices','0008_daily_baselines','0009_gold','0010_gullak_silver','0011_hdfc','0012_indmoney','0013_indmoney_sync']) db.exec(readFileSync(new URL('../../migrations/'+name+'.sql',import.meta.url),'utf8'));
 const env = {DB:{prepare(sql:string){let args:any[]=[]; return {bind(...values:any[]){args=values;return this;},async first<T>(){return db.prepare(sql).get(...args) as T ?? null;},async run(){return db.prepare(sql).run(...args);}};}}};
 return {db,env};
}
