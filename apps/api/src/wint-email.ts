import {Decimal} from 'decimal.js';
import {validDay} from './gold-prices';
import {istDate} from './daily-prices';
export type WintPurchase={kind:'purchase';key:string;isin:string;name:string;accountID:string;confirmed:boolean;date:string;orderDate:string;quantity:string;faceValue:string;cleanCost:string;invested:string;accrued:string;coupon:string;frequency:string;repayment:string;maturesOn:string};
export type WintPayout={kind:'interest'|'principal'|'redemption';key:string;isin:string;date:string;gross:string;tds:string;net:string;principal:string;nextPayout:string|null;reconciliationDifference:string};
export type WintEvent=WintPurchase|WintPayout;
export type MailPart={headers?:{name:string;value:string}[];mimeType?:string;body?:{data?:string};parts?:MailPart[]};
export function trustedWintMessage(payload:MailPart) {
 const values=(name:string)=>(payload.headers??[]).filter(h=>h.name.toLowerCase()===name).map(h=>h.value.trim());
 const from=values('from'),auth=values('authentication-results').filter(v=>/^mx\.google\.com\s*;/i.test(v)),subject=values('subject');
 return from.length===1 && /^(?:[^<>]*<)?(?:transactions|receipts)@wintwealth\.com>?$/i.test(from[0]) && subject.length===1
 && /^(?:Investment Successful for |Your order receipt for |(?:💸\s*)?(?:Just Credited:|Asset Matured:))/.test(subject[0])
 && auth.length===1 && /dmarc=pass\b[^;]*\bheader\.from=wintwealth\.com(?:\s|;|$)/i.test(auth[0]);
}
export function emailText(raw:string) {
 if(raw.length>500000)throw Error('Email too large.');
 return raw.replace(/<style\b[\s\S]*?<\/style>/gi,' ').replace(/<script\b[\s\S]*?<\/script>/gi,' ').replace(/<[^>]*>/g,' ')
 .replace(/&#(x[0-9a-f]+|\d+);/gi,(_,n)=>{const code=n[0].toLowerCase()==='x'?parseInt(n.slice(1),16):Number(n);return code>0 && code<=0x10ffff?String.fromCodePoint(code):' ';})
 .replace(/&(?:nbsp|amp|lt|gt|quot|apos);/g,m=>({'&nbsp;':' ','&amp;':'&','&lt;':'<','&gt;':'>','&quot;':'"','&apos;':"'"}[m]!)).replace(/\s+/g,' ').trim();
}
export function gmailBody(payload:MailPart):string {
 const parts:MailPart[]=[];const walk=(p:MailPart)=>{if(['text/plain','text/html'].includes(p.mimeType??'') && p.body?.data)parts.push(p);for(const child of p.parts??[])walk(child);};walk(payload);
 const plain=parts.filter(p=>p.mimeType==='text/plain'),chosen=plain.length?plain:parts;
 if(chosen.length!==1)throw Error('Ambiguous email body.');
 const data=chosen[0].body!.data!;if(data.length>700000 || !/^[A-Za-z0-9_=-]+$/.test(data))throw Error('Invalid email bytes.');
 return new TextDecoder().decode(Uint8Array.from(atob(data.replaceAll('-','+').replaceAll('_','/')),c=>c.charCodeAt(0)));
}
function single(text:string,pattern:RegExp) {
 const all=[...text.matchAll(new RegExp(pattern.source,'g'))];if(all.length!==1)throw Error('Missing or duplicate Wint field.');return all[0];
}
function day(raw:string) {
 const match=/^(\d{2})-([A-Z][a-z]{2})-(\d{4})$/.exec(raw),months=['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
 if(!match)throw Error('Invalid Wint date.');const value=`${match[3]}-${String(months.indexOf(match[2])+1).padStart(2,'0')}-${match[1]}`;
 if(!validDay(value))throw Error('Invalid Wint date.');return value;
}
const num=(s:string)=>new Decimal(s.replaceAll(',',''));
export function parseWintEmail(subject:string,raw:string,at=new Date()):WintEvent {
 const text=emailText(raw),isin=single(text,/\bISIN (IN[A-Z0-9]{10})\b/)[1];
 const money=(label:string)=>num(single(text,new RegExp(label+' ₹\\s*(-?[\\d,]+(?:\\.\\d+)?)'))[1]);
 if(subject.startsWith('Investment Successful for ') || subject.startsWith('Your order receipt for ')) {
  const confirmed=subject.startsWith('Investment Successful for ');
  if(confirmed && !text.includes('settlement process has been completed, and securities have been credited to your Wint Wealth Demat Account.'))throw Error('Purchase not settled.');
  const order=single(text,/\bOrder ID (\d+)\b/)[1],name=single(text,/PRODUCT NAME (.+?) ISIN /)[1];
  const orderDate=day(single(text,/ORDER DATE AND TIME (\d{2}-[A-Z][a-z]{2}-\d{4}) /)[1]);
  const date=confirmed?day(single(text,/SETTLEMENT DATE AND TIME (\d{2}-[A-Z][a-z]{2}-\d{4}) /)[1]):orderDate;
  if(date<orderDate || date>istDate(at))throw Error('Invalid settlement date.');
  const account=single(text,/BUYER SETTLEMENT DETAILS DP ID: (IN\d{6}) CLIENT ID: (\d{8})\b/);
  const quantity=num(single(text,/NUMBER OF UNITS ([\d,]+) ORDER DATE/)[1]),face=money('FACE VALUE PER UNIT'),clean=money('CLEAN PRICE PER UNIT'),accrued=money('TOTAL ACCRUED INTEREST(?:/EX INTEREST)?');
  const invested=money('TOTAL INVESTMENT AMOUNT \\(INCLUSIVE OF STAMP DUTY(?: AND BROKERAGE)?\\)'),principal=money('TOTAL PRINCIPAL AMOUNT'),consideration=money('TOTAL CONSIDERATION'),stamp=money('STAMP DUTY \\(TO BE PAID BY BUYER\\)');
  const brokerage=text.includes('BROKERAGE (INCLUSIVE OF GST)')?money('BROKERAGE \\(INCLUSIVE OF GST\\)'):new Decimal(0);
  const coupon=num(single(text,/COUPON RATE (\d+(?:\.\d+)?)%/)[1]);
  if(quantity.lte(0) || face.lte(0) || clean.lte(0) || invested.lte(0) || stamp.lt(0) || brokerage.lt(0) || coupon.lt(0) || coupon.gt(50)
   || !quantity.times(face).eq(principal) || quantity.times(clean).plus(accrued).minus(consideration).abs().gt('.03') || consideration.plus(stamp).plus(brokerage).minus(invested).abs().gt('.03'))throw Error('Purchase totals do not reconcile.');
  const frequency=single(text,/INTEREST PAYMENT DATE (.+?) MATURITY DATE/)[1],repayment=single(text,/PRINCIPAL REPAYMENT (.+?) INTEREST PAYMENT DATE/)[1],maturesOn=day(single(text,/MATURITY DATE (\d{2}-[A-Z][a-z]{2}-\d{4}) NUMBER OF UNITS/)[1]);
  if(maturesOn<date)throw Error('Purchase after maturity.');
  return {kind:'purchase',key:'purchase:'+order,isin,name,accountID:account[1]+account[2],confirmed,date,orderDate,quantity:quantity.toFixed(),faceValue:face.toFixed(),cleanCost:quantity.times(clean).toFixed(),invested:invested.toFixed(),accrued:accrued.toFixed(),coupon:coupon.toFixed(),frequency,repayment,maturesOn};
 }
 if(!/^(?:💸\s*)?(?:Just Credited:|Asset Matured:)/.test(subject))throw Error('Unsupported Wint email.');
 const date=day(single(text,/Date of payout (\d{2}-[A-Z][a-z]{2}-\d{4})\b/)[1]);if(date>istDate(at))throw Error('Future payout.');
 const gross=money('Interest amount \\(Pre-TDS\\)'),tds=money('TDS deducted'),total=money('Total amount credited:');
 const principal=text.includes('Principal repaid ₹')?money('Principal repaid'):new Decimal(0),net=text.includes('Interest amount credited ₹')?money('Interest amount credited'):total.minus(principal);
 const difference=gross.minus(tds).minus(net).abs().plus(principal.plus(net).minus(total).abs());
 if(gross.lt(0) || tds.lt(0) || net.lt(0) || principal.lt(0) || difference.gt(1))throw Error('Payout does not reconcile.');
 const kind=subject.includes('Asset Matured:')?'redemption':principal.gt(0)?'principal':'interest';
 if(kind==='redemption' && principal.lte(0))throw Error('Redemption principal missing.');
 const next=/Next payout date (\d{2}-[A-Z][a-z]{2}-\d{4})\b/.exec(text),nextPayout=next?day(next[1]):null;
 if(nextPayout && nextPayout<=date)throw Error('Invalid next payout.');
 return {kind,key:`${kind}:${isin}:${date}`,isin,date,gross:gross.toFixed(),tds:tds.toFixed(),net:net.toFixed(),principal:principal.toFixed(),nextPayout,reconciliationDifference:difference.toFixed()};
}
