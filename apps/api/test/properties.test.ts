import {test} from 'node:test';
import assert from 'node:assert/strict';
import {app} from '../src/index';
import {setupGold} from './helpers/database';
import {digest} from '../src/zerodha';
const id='11111111-1111-4111-8111-111111111111';
const property={name:'Apartment',estimatedValue:'10000000',valuationDate:'2026-10-01',purchaseCost:'8000000'};
async function setup(){const {env,db}=setupGold();for(const token of ['one','two'])db.prepare('INSERT INTO zerodha_sessions(token_hash,encrypted_token,owner_id,expires_at,provider_expires_at) VALUES(?,?,?,?,?)').run(await digest(token==='one'?'1'.repeat(64):'2'.repeat(64)),'unused',token,Date.now()+86400000,0);return {env,db,call:(path:string,method='GET',body?:unknown,token='one')=>app.request('/v1/properties'+path,{method,headers:{Authorization:'Bearer '+(token==='one'?'1'.repeat(64):token==='two'?'2'.repeat(64):token),'Content-Type':'application/json'},body:body===undefined?undefined:JSON.stringify(body)},env as any)};}
test('manual property CRUD validates input, isolates owners and preserves previous data on invalid edits',async()=>{
 const {call}=await setup();assert.equal((await call('','GET',undefined,'missing')).status,401);
 assert.equal((await call('/'+id,'PUT',property)).status,200);
 let list=await (await call('')).json() as any;assert.equal(list.properties.length,1);assert.equal(list.properties[0].estimatedValue,'10000000');
 assert.equal(((await (await call('','GET',undefined,'two')).json()) as any).properties.length,0);
 assert.equal((await call('/'+id,'DELETE',undefined,'two')).status,404);
 for(const patch of [{estimatedValue:'NaN'},{name:' '},{valuationDate:'2099-01-01'},{valuationDate:'2026-02-30'},{purchaseCost:'-1'}])assert.equal((await call('/'+id,'PUT',{...property,...patch})).status,400);
 assert.equal(((await (await call('')).json()) as any).properties[0].name,'Apartment');
 assert.equal((await call('/'+id,'PUT',{...property,name:'Updated'})).status,200);
 list=await (await call('')).json() as any;assert.equal(list.properties.length,1);assert.equal(list.properties[0].name,'Updated');
 assert.equal((await call('/'+id,'DELETE')).status,200);assert.equal(((await (await call('')).json()) as any).properties.length,0);
});

import {propertiesPortfolio} from '../src/properties';
import {zerodhaSnapshot} from '../src/zerodha-portfolio';
import {revalue} from '../src/portfolio-valuation';
test('full property valuations update net worth and allocation without duplication, market repricing or stale sold properties',async()=>{
 const {call,env}=await setup();await call('/'+id,'PUT',property);
 const base=zerodhaSnapshot('{"status":"success","data":[]}','{"status":"success","data":[]}',new Date('2026-10-10T00:00:00Z'));
 const portfolio=await propertiesPortfolio(env,base,'one');
 assert.equal(portfolio.value,'10000000');assert.equal(portfolio.allocation[0].assetClass,'realEstate');assert.equal(portfolio.allocation[0].value,'10000000');
 assert.equal(portfolio.holdings[0].propertyTerms?.purchaseCost,'8000000');assert.equal(portfolio.holdings[0].gain,null);
 assert.equal((await propertiesPortfolio(env,portfolio,'one')).holdings.length,1);
 assert.equal((await propertiesPortfolio(env,base,'two')).holdings.length,0);
 assert.equal(revalue(portfolio,[]).value,'10000000');
 await call('/'+id,'PUT',{...property,estimatedValue:'12000000',ownershipPercent:'25'});
 assert.equal((await propertiesPortfolio(env,portfolio,'one')).value,'12000000');
 await call('/'+id,'DELETE');assert.equal((await propertiesPortfolio(env,portfolio,'one')).holdings.length,0);
 assert.equal((await propertiesPortfolio(env,portfolio,'one')).value,'0');
});

 test('legacy ownership percentages are ignored and optional classification/location persist',async()=>{
  const {call,env,db}=await setup();
  const legacy={...property,ownershipPercent:'25'};
  db.prepare('INSERT INTO properties VALUES(?,?,?,?)').run('one',id,JSON.stringify({...legacy,id,updatedAt:0}),0);
  const base=zerodhaSnapshot('{"status":"success","data":[]}','{"status":"success","data":[]}',new Date('2026-10-10T00:00:00Z'));
  assert.equal((await propertiesPortfolio(env,base,'one')).value,'10000000');
  const saved=await (await call('/'+id,'PUT',{...property,classification:'house',location:'Bengaluru, KA'})).json() as any;
  assert.equal(saved.property.classification,'house');assert.equal(saved.property.location,'Bengaluru, KA');
  assert.equal(saved.property.ownershipPercent,'100');
  for(const patch of [{classification:'invalid'},{location:123},{location:'x'.repeat(101)}])assert.equal((await call('/'+id,'PUT',{...property,...patch})).status,400);
 });
