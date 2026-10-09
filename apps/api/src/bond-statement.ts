import {Decimal} from 'decimal.js';
import {validDay} from './gold-prices';
import {istDate} from './daily-prices';
function day(raw:string) {
 const [d,m,y]=raw.split('-'),value=`${y}-${m}-${d}`;
 if(!validDay(value))throw new Error('Invalid CAS date.');return value;
}
const amount=(value:string)=>new Decimal(value.replaceAll(',',''));
// Initial supported layout: one NSDL account containing NCDs, reconciled to the
// entire CAS debt allocation. Mixed/extra accounts fail closed instead of losing bonds.
export function parseBondStatement(raw:string,at=new Date()) {
 const text=raw.replace(/\s+/g,' ').trim();
 if(!text.includes('CONSOLIDATED ACCOUNT STATEMENT (CAS)'))throw new Error('Unsupported CAS.');
 const summaries=[...text.matchAll(/NSDL Demat Account (.+?) DP Id:\s*(IN\d{6}) Client Id\s*:\s*(\d{8}) (\d+) ([\d,]+\.\d{2})/g)];
 if(summaries.length!==1)throw new Error('Unsupported NSDL accounts.');
 const summary=summaries[0],accountID=summary[2]+summary[3],count=Number(summary[4]);
 const debt=/\bAsset Class Value Percentage Debts ([\d,]+\.\d{2})\b/.exec(text);
 const start=text.indexOf('DEMAT ACCOUNTS HELD WITH NSDL');
 const section=text.slice(start),ids=[...new Set([...section.matchAll(/DPID\s*:\s*(IN\d{14})/g)].map(m=>m[1]))];
 if(start<0 || ids.length!==1 || ids[0]!==accountID)throw new Error('CAS account mismatch.');
 if(count===0) {
  const period=/STATEMENT OF TRANSACTIONS FOR THE PERIOD FROM (\d{2}-\d{2}-\d{4}) TO (\d{2}-\d{2}-\d{4})/.exec(section);
  if(!period || !section.includes('Nil Holding') || !debt || !amount(debt[1]).isZero() || !amount(summary[5]).isZero())throw new Error('Unconfirmed empty bond account.');
  const statementDate=day(period[2]);
  if(day(period[1])>statementDate || statementDate>istDate(at))throw new Error('Invalid empty CAS date.');
  return {accountID,statementDate,total:'0',bonds:[]};
 }
 const header=/HOLDING STATEMENT AS ON (\d{2}-\d{2}-\d{4})/.exec(section);
 const footer=/Portfolio Value [`₹‘] ([\d,]+\.\d{2}) as on (\d{2}-\d{2}-\d{4})/.exec(section);
 if(!header || !footer || footer.index<header.index)throw new Error('Missing CAS closing holdings.');
 const statementDate=day(header[1]);
 if(header[1]!==footer[2] || statementDate>istDate(at))throw new Error('Invalid CAS valuation date.');
 const total=amount(footer[1]);
 if(!debt || !total.eq(amount(debt[1])) || !total.eq(amount(summary[5])))throw new Error('CAS debt totals do not reconcile.');
 const body=section.slice(header.index+header[0].length,footer.index);
 const isinPattern=/\b(IN[EF](?: ?[A-Z0-9]){9})\b/g;
 const isins=[...body.matchAll(isinPattern)];
 if(isins.length!==count || count<1 || count>200)throw new Error('Incomplete CAS holdings.');
 const seen=new Set<string>();
 const bonds=isins.map((match,i)=>{
  const isin=match[1].replaceAll(' ','');
  if(seen.has(isin))throw new Error('Duplicate bond.');seen.add(isin);
  const row=body.slice(match.index!+match[0].length,isins[i+1]?.index??body.length);
  // Current balance + nine blocked/pending buckets + free units + stated price/value.
  const numbers=/^(.*?) ([\d,]+(?:\.\d+)?) ((?:(?:--|0(?:\.0+)?) ){9})([\d,]+(?:\.\d+)?) ([\d,]+(?:\.\d+)?) ([\d,]+\.\d{2})(?= |$)/.exec(' '+row.trim());
  if(!numbers || !/\bNCD\b/.test(numbers[1]))throw new Error('Unsupported bond row.');
  const description=numbers[1].trim(),quantity=amount(numbers[2]),free=amount(numbers[4]),price=amount(numbers[5]),value=amount(numbers[6]);
  if(quantity.lte(0) || !quantity.eq(free) || price.lte(0) || quantity.times(price).minus(value).abs().gt('0.01'))throw new Error('Bond value does not reconcile.');
  const coupon=/([\d]+(?:\.\d+)?)%/.exec(description)?.[1]??(/ZERO COUP/.test(description)?'0':null);
  const maturity=/\bRD\s*(\d{2}-\d{2}-\d{4})\b/.exec(description)?.[1];
  const name=description.split('#')[0].replace(/\s+\d+(?:\.\d+)? NCD\b.*$/,'').trim();
  return {isin,name,quantity:quantity.toFixed(),price:price.toFixed(),value:value.toFixed(),coupon,maturesOn:maturity?day(maturity):null};
 });
 if(!bonds.reduce((sum,b)=>sum.plus(b.value),new Decimal(0)).eq(total))throw new Error('CAS holdings total mismatch.');
 return {accountID,statementDate,total:total.toFixed(),bonds};
}
