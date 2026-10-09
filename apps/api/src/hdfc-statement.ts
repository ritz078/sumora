import {Decimal} from 'decimal.js';
import {validDay} from './gold-prices';
import {istDate} from './daily-prices';
function date(value:string) {
 const m=/^(\d{2})\/(\d{2})\/(\d{4})$/.exec(value);
 const day=m?`${m[3]}-${m[2]}-${m[1]}`:'';
 if(!validDay(day))throw new Error('Invalid HDFC statement date.');return day;
}
function money(value:string) {
 if(!/^(?:\d+|\d{1,3}(?:,\d{2,3})+)\.\d{2}$/.test(value))throw new Error('Invalid HDFC amount.');
 return new Decimal(value.replaceAll(',','')).toFixed();
}
export function parseHDFCStatement(raw:string,at=new Date()) {
 const text=raw.replace(/\s+/g,' ').trim();
 if(!text.includes('Account Relationship Summary') || !text.includes('Your Combined statement generation frequency is monthly') || !text.includes('*** End of Statement ***'))throw new Error('Unrecognized HDFC combined statement.');
 const dates=[...text.matchAll(/Statement as on\s*(?::\s*(\d{2}\/\d{2}\/\d{4})|Customer Email Customer ID Account Relationship Summary\s*:\s*(\d{2}\/\d{2}\/\d{4}))/g)].map(m=>date(m[1]??m[2]));
 if(!dates.length || new Set(dates).size!==1 || dates[0]>istDate(at))throw new Error('Inconsistent HDFC statement date.');
 const summary=[...text.matchAll(/INR TERM DEPOSITS ([0-9,.]+) CR/g)];
 if(summary.length!==1)throw new Error('Missing or duplicate HDFC term deposit summary.');
 const total=money(summary[0][1]);
 const start=text.indexOf('FD DETAILS :- FOR CURRENT FINANCIAL YEAR'),end=text.indexOf('# Current Principal is net of Withdrawals',start);
 if(start<0 && total==='0' && !/\b\d{10,20} INR\b/.test(text))return {date:dates[0],total,deposits:[] as {number:string;originalPrincipal:string;currentAmount:string;withdrawable:string;maturityAmount:string;rate:string;openedOn:string;maturesOn:string;lien:string;nomination:boolean}[]};
 if(start<0 || end<0)throw new Error('Missing complete HDFC FD section.');
 const section=text.slice(start,end);
 const amount='([0-9,.]+)',day='(\\d{2}/\\d{2}/\\d{4})';
 const row=new RegExp('(\\d{10,20}) INR '+amount+' '+day+' ([0-9.]+) '+amount+' '+amount+' (YES|NO) '+amount+' '+day+' '+amount,'g');
 const matches=[...section.matchAll(row)];
 const candidates=[...section.matchAll(/\b\d{10,20}\s+[A-Z]{3}\b/g)];
 if(matches.length!==candidates.length || !matches.length && total!=='0')throw new Error('Unparsed HDFC FD rows.');
 const seen=new Set<string>();
 const deposits=matches.map(m=>{
  if(seen.has(m[1]))throw new Error('Duplicate HDFC FD.');seen.add(m[1]);
  const rate=new Decimal(m[4]),openedOn=date(m[3]),maturesOn=date(m[9]);
  if(!rate.isFinite() || rate.lt(0) || rate.gt(100) || openedOn>dates[0] || openedOn>=maturesOn)throw new Error('Invalid HDFC FD terms.');
  const result={number:m[1],originalPrincipal:money(m[2]),currentAmount:money(m[8]),withdrawable:money(m[10]),maturityAmount:money(m[6]),rate:rate.toFixed(),openedOn,maturesOn,lien:money(m[5]),nomination:m[7]==='YES'};
  if(new Decimal(result.withdrawable).gt(result.currentAmount) || new Decimal(result.lien).gt(result.currentAmount))throw new Error('Invalid HDFC FD balances.');
  return result;
 });
 if(!deposits.reduce((sum,d)=>sum.plus(d.withdrawable),new Decimal(0)).eq(total))throw new Error('HDFC FD summary does not reconcile.');
 return {date:dates[0],total,deposits};
}
