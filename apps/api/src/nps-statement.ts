import {Decimal} from 'decimal.js';
import {validDay} from './gold-prices';
import {istDate} from './daily-prices';
function day(value:string) {
 const numeric=/^(\d{2})-(\d{2})-(\d{4})$/.exec(value);
 const months=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
 const named=/^([A-Z][a-z]{2}) (\d{2}), (\d{4})$/.exec(value);
 const result=numeric?`${numeric[3]}-${numeric[2]}-${numeric[1]}`:named?`${named[3]}-${String(months.indexOf(named[1])+1).padStart(2,'0')}-${named[2]}`:'';
 if(!validDay(result))throw new Error('Invalid NPS date.');return result;
}
export function parseNPSStatement(raw:string,at=new Date()) {
 const text=raw.replace(/\s+/g,' ').trim();
 const tier=/Transaction Statement - Tier (II|I)\b/.exec(text)?.[1];
 const pran=/\bPRAN (\d{12})\b/.exec(text)?.[1];
 const statement=/Statement Date ([A-Z][a-z]{2} \d{2}, \d{4})/.exec(text)?.[1];
 const valuation=/Investment Details as on (\d{2}-\d{2}-\d{4})/.exec(text)?.[1];
 if(!text.includes('NATIONAL PENSION SYSTEM') || !text.includes('KFintech') || !tier || !pran || !statement || !valuation)throw new Error('Unsupported NPS statement.');
 const statementDate=day(statement),valuationDate=day(valuation);
 if(valuationDate>statementDate || statementDate>istDate(at))throw new Error('Invalid NPS valuation date.');
 const start=text.indexOf('Scheme Name Total Units Latest NAV Value at NAV'),end=text.indexOf('Changes made during selected period',start);
 if(start<0 || end<0)throw new Error('Incomplete NPS investment section.');
 const section=text.slice(start,end),totalMatch=/ Total ([\d,]+\.\d{2})\s*$/.exec(section);
 if(!totalMatch)throw new Error('Missing NPS total.');
 const total=new Decimal(totalMatch[1].replaceAll(',','')).toFixed();
 const body=section.slice(0,totalMatch.index).replace(/^Scheme Name Total Units Latest NAV Value at NAV(?: XIRR)? /,'');
 const rows=[...body.matchAll(/(NPS TRUST- A\/C [A-Z0-9 &().-]+? SCHEME ([A-Z]) - TIER (II|I)) POP ([\d,]+\.\d+) ([\d,]+\.\d+) ([\d,]+\.\d{2})(?: -?\d+\.\d+%)?(?= NPS TRUST|$)/g)];
 const seen=new Set<string>();
 const schemes=rows.map(m=>{
  const name=m[1],id=m[2];
  if(m[3]!==tier || seen.has(id))throw new Error('Ambiguous NPS scheme.');seen.add(id);
  const [quantity,nav,value]=[m[4],m[5],m[6]].map(n=>new Decimal(n.replaceAll(',','')));
  if(quantity.lt(0) || nav.lte(0) || value.lt(0) || quantity.times(nav).minus(value).abs().gt('0.01'))throw new Error('NPS NAV does not reconcile.');
  return {name,code:id,quantity:quantity.toFixed(),nav:nav.toFixed(),value:value.toFixed()};
 });
 if(!schemes.length || body.replace(/(NPS TRUST- A\/C [A-Z0-9 &().-]+? SCHEME [A-Z] - TIER (?:II|I)) POP [\d,]+\.\d+ [\d,]+\.\d+ [\d,]+\.\d{2}(?: -?\d+\.\d+%)?/g,'').trim())throw new Error('Unparsed NPS scheme rows.');
 const summaryRow=/Notional Gain\/Loss \(₹\) \d+ ([\d,.]+) ([\d,.]+) ([\d,.]+) ([\d,.]+) (-?[\d,.]+)/.exec(text);
 if(!summaryRow)throw new Error('Missing NPS contribution summary.');
 const [contributions,withdrawals,charges,summaryValue,gain]=summaryRow.slice(1).map(n=>new Decimal(n.replaceAll(',','')));
 const invested=contributions.minus(withdrawals);
 if(contributions.lt(0) || withdrawals.lt(0) || charges.lt(0) || invested.lt(0) || !summaryValue.eq(total) || !summaryValue.minus(invested).eq(gain) || !schemes.reduce((s,v)=>s.plus(v.value),new Decimal(0)).eq(total))throw new Error('NPS totals do not reconcile.');
 const rates=[...new Set([...body.matchAll(/(-?\d+\.\d+)%/g)].map(m=>new Decimal(m[1]).toFixed()))];
 const summary={invested:invested.toFixed(),gain:gain.toFixed(),xirr:rates.length===1?rates[0]:null};
 return {tier,pran,statementDate,valuationDate,total,schemes,summary};
}
