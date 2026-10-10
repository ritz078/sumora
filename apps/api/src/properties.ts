import {Hono} from 'hono';
import {Decimal} from 'decimal.js';
import {APIError,appSession,type KiteEnvironment} from './zerodha';
import {validDay} from './gold-prices';
import {istDate} from './daily-prices';
import {portfolioTotals,type Portfolio} from './portfolio-valuation';
export type PropertyEntry={id:string;name:string;estimatedValue:string;ownershipPercent:string;valuationDate:string;purchaseCost:string|null;updatedAt:number};
const uuid=/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/i;
function entry(raw:unknown,id:string,at:Date):PropertyEntry {
 if(!raw || typeof raw!=='object' || Array.isArray(raw))throw new APIError(400,'INVALID_PROPERTY','Enter property details.');
 const v=raw as Record<string,unknown>;
 const amount=(key:string,max:string)=>{
  const value=v[key];if(typeof value!=='string' || !/^\d{1,13}(?:\.\d{1,4})?$/.test(value))throw new APIError(400,'INVALID_PROPERTY','Enter valid positive amounts and ownership.');
  const n=new Decimal(value);if(n.gt(max))throw new APIError(400,'INVALID_PROPERTY','Property amount or ownership is too large.');return n;
 };
 const estimated=amount('estimatedValue','1000000000000'),ownership=amount('ownershipPercent','100');
 if(ownership.lte(0) || typeof v.name!=='string' || !v.name.trim() || v.name.trim().length>80 || /[\x00-\x1f]/.test(v.name))throw new APIError(400,'INVALID_PROPERTY','Enter a property name and ownership between 0 and 100 percent.');
 if(typeof v.valuationDate!=='string' || !validDay(v.valuationDate) || v.valuationDate>istDate(at))throw new APIError(400,'INVALID_PROPERTY','Choose a valid valuation date that is not in the future.');
 const purchase=v.purchaseCost==null || v.purchaseCost===''?null:amount('purchaseCost','1000000000000').toFixed();
 return {id,name:v.name.trim(),estimatedValue:estimated.toFixed(),ownershipPercent:ownership.toFixed(),valuationDate:v.valuationDate,purchaseCost:purchase,updatedAt:at.getTime()};
}
export async function propertyEntries(env:Pick<KiteEnvironment,'DB'>,owner:string):Promise<PropertyEntry[]> {
 const row=await env.DB.prepare("SELECT json_group_array(json(data)) AS properties FROM (SELECT data FROM properties WHERE owner_id=? ORDER BY updated_at DESC,id)").bind(owner).first<{properties:string}>();return JSON.parse(row?.properties??'[]');
}
export async function propertiesPortfolio(env:Pick<KiteEnvironment,'DB'>,snapshot:Portfolio,owner:string):Promise<Portfolio> {
 const entries=await propertyEntries(env,owner);
 if(!entries.length && !snapshot.holdings.some(h=>h.accountID==='properties') && !snapshot.connections.some(c=>c.id==='properties'))return snapshot;
 const holdings:Portfolio['holdings']=entries.map(p=>({id:'property:'+p.id,name:p.name,symbol:'PROPERTY',assetClass:'realEstate',accountID:'properties',quantity:p.ownershipPercent,unit:'% ownership',invested:'0',costBasisKnown:false,value:new Decimal(p.estimatedValue).times(p.ownershipPercent).div(100).toDecimalPlaces(2).toFixed(),gain:null,gainPercent:null,quote:null,quoteAt:p.valuationDate+'T00:00:00Z',quoteCurrency:'INR',fxRate:'1',fxAt:null,history:[],source:'Manually entered',priceBasis:`Estimated property value × ownership share. Valuation dated ${p.valuationDate}; no automatic appreciation.`,propertyTerms:p}));
 return portfolioTotals({...snapshot,holdings:[...snapshot.holdings.filter(h=>h.accountID!=='properties'),...holdings],connections:[...snapshot.connections.filter(c=>c.id!=='properties'),...(entries.length?[{id:'properties',name:'Manual real estate',symbol:'P',status:'connected',lastSyncAt:new Date(Math.max(...entries.map(p=>p.updatedAt))).toISOString(),description:'Manually entered valuations, adjusted for your ownership share.'}]:[])]});
}
export function propertiesRoutes(now=Date.now) {
 const app=new Hono<{Bindings:KiteEnvironment}>();
 app.onError((error,c)=>{const e=error instanceof APIError?error:new APIError(500,'PROPERTY_FAILED','Unable to update properties. Previous data is retained.');return c.json({error:{code:e.code,message:e.message}},e.status);});
 app.get('/',async c=>{const auth=await appSession(c.env,c.req.header('Authorization'),now);return c.json({properties:await propertyEntries(c.env,auth.owner_id)});});
 app.put('/:id',async c=>{
  const auth=await appSession(c.env,c.req.header('Authorization'),now),id=c.req.param('id');
  if(!uuid.test(id))throw new APIError(400,'INVALID_PROPERTY','Invalid property identifier.');
  const text=await c.req.text();if(text.length>2048)throw new APIError(400,'INVALID_PROPERTY','Property details are too long.');
  let raw:unknown;try{raw=JSON.parse(text);}catch{throw new APIError(400,'INVALID_PROPERTY','Enter valid property details.');}
  const value=entry(raw,id,new Date(now()));
  const result=await c.env.DB.prepare(`INSERT INTO properties(owner_id,id,data,updated_at) SELECT ?,?,?,? WHERE (SELECT count(*) FROM properties WHERE owner_id=?)<50 OR EXISTS(SELECT 1 FROM properties WHERE owner_id=? AND id=?) ON CONFLICT(owner_id,id) DO UPDATE SET data=excluded.data,updated_at=excluded.updated_at RETURNING id`).bind(auth.owner_id,id,JSON.stringify(value),now(),auth.owner_id,auth.owner_id,id).first();
  if(!result)throw new APIError(409,'PROPERTY_LIMIT','You can record up to 50 properties.');
  return c.json({property:value});
 });
 app.delete('/:id',async c=>{const auth=await appSession(c.env,c.req.header('Authorization'),now);const row=await c.env.DB.prepare('DELETE FROM properties WHERE owner_id=? AND id=? RETURNING id').bind(auth.owner_id,c.req.param('id')).first();if(!row)throw new APIError(404,'PROPERTY_NOT_FOUND','Property not found.');return c.json({removed:true});});
 return app;
}
