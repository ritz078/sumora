import {Decimal} from 'decimal.js';
import {istDate} from './daily-prices';
import type {parseBondStatement} from './bond-statement';
import type {StoredEvent,StoredPurchase} from './wint-events';
import type {WintPayout} from './wint-email';
import type {Portfolio} from './portfolio-valuation';
type CAS=ReturnType<typeof parseBondStatement>;
const sum=(values:string[])=>values.reduce((s,v)=>s.plus(v),new Decimal(0));
export function reconcileBonds(cas:CAS|null,accountHash:string|null,events:StoredEvent[],at=new Date()) {
 const holdings:Portfolio['holdings']=[];
 const redeemed:{isin:string;name:string;date:string;principal:string;interestNet:string;tds:string}[]=[];
 if(!cas || !accountHash)return {holdings,redeemed};
 const today=istDate(at);
 const purchases=events.filter(e=>e.event.kind==='purchase' && e.accountHash===accountHash).map(e=>e.event as StoredPurchase).filter(p=>p.date<=cas.statementDate);
 const payouts=events.map(e=>e.event).filter((e):e is WintPayout=>e.kind!=='purchase' && e.date<=today);
 for(const base of cas.bonds) {
  const isin=base.isin,lots=purchases.filter(p=>p.isin===isin).sort((a,b)=>a.date.localeCompare(b.date)),confirmed=lots.filter(p=>p.confirmed);
  // A receipt is corroborated only when the complete pre-CAS quantity matches.
  const matched=sum(lots.map(p=>p.quantity)).eq(base.quantity)?lots:sum(confirmed.map(p=>p.quantity)).eq(base.quantity)?confirmed:[];
  const known=matched.length>0;
  const ytm=known && matched.every(p=>p.ytm!=null && p.ytm===matched[0].ytm)?matched[0].ytm??null:null;
  // Terminal wealth assumes all interim payments are reinvested at each lot's
  // purchase YTM. ACT/365 and annual compounding are estimates, before tax.
  const projectionStart=(p:StoredPurchase)=>p.confirmed?p.date:p.orderDate;
  const projectable=known && matched.every(p=>p.ytm!=null && projectionStart(p)<=p.maturesOn);
  const projectionUsesOrderDate=projectable && matched.some(p=>!p.confirmed);
  const projectedMaturityValue=projectable?sum(matched.map(p=>{
   const years=new Decimal(Date.parse(p.maturesOn+'T00:00:00Z')-Date.parse(projectionStart(p)+'T00:00:00Z')).div(86400000).div(365);
   return new Decimal(p.invested).times(new Decimal(p.ytm!).div(100).plus(1).pow(years)).toFixed();
  })).toDecimalPlaces(2).toFixed():null;
  // Exclude cash flows from prior ownership. Without matched lots, show only
  // post-CAS payments and never use them as proof of complete principal repayment.
  const start=matched[0]?.date??cas.statementDate;
  const flows=payouts.filter(p=>p.isin===isin && p.date>=start).sort((a,b)=>a.date.localeCompare(b.date));
  const full=flows.filter(f=>f.kind==='redemption').at(-1),newest=matched.at(-1);
  const principal=sum(flows.map(f=>f.principal)),face=sum(matched.map(p=>new Decimal(p.quantity).times(p.faceValue).toFixed()));
  const fullyRepaid=!!full && known && principal.eq(face) && full.date>=newest!.date;
  if(fullyRepaid && full!.date>cas.statementDate) {
   redeemed.push({isin,name:base.name,date:full!.date,principal:principal.toFixed(),interestNet:sum(flows.map(f=>f.net)).toFixed(),tds:sum(flows.map(f=>f.tds)).toFixed()});continue;
  }
  const pendingPrincipal=flows.some(f=>new Decimal(f.principal).gt(0) && f.date>cas.statementDate);
  const note=pendingPrincipal?'Principal repayment recorded; remaining value awaits reconciliation.':!known?'Purchase quantities do not fully reconcile; invested amount unavailable.':null;
  const maturity=base.maturesOn??newest?.maturesOn??null;
  holdings.push({id:'bonds:'+isin,name:base.name,symbol:isin,assetClass:'bond',accountID:'bonds',quantity:base.quantity,unit:'bonds',invested:'0',costBasisKnown:false,value:projectedMaturityValue??base.value,gain:null,gainPercent:null,quote:base.price,quoteAt:cas.statementDate+'T00:00:00Z',quoteCurrency:'INR',fxRate:'1',fxAt:null,history:[],source:'CDSL CAS · NSDL',priceBasis:projectedMaturityValue?`Projected maturity wealth at purchase YTM; assumes reinvestment of all payouts before tax. CAS determines holdings as of ${cas.statementDate}.`:`CAS recorded purchase value as of ${cas.statementDate}; maturity projection unavailable. Interest and principal receipts are shown separately.`,bondTerms:{ytm,projectedMaturityValue,projectionUsesOrderDate,coupon:base.coupon??newest?.coupon??null,maturesOn:maturity,redemptionCheck:!!maturity && maturity<=today,investedAmount:known?sum(matched.map(p=>p.invested)).toFixed():null,accruedAtPurchase:known?sum(matched.map(p=>p.accrued)).toFixed():null,interestGross:sum(flows.map(f=>f.gross)).toFixed(),interestNet:sum(flows.map(f=>f.net)).toFixed(),tds:sum(flows.map(f=>f.tds)).toFixed(),principalReceived:principal.toFixed(),nextPayout:flows.at(-1)?.nextPayout??null,frequency:newest?.frequency??null,repayment:newest?.repayment??null,quotedCoupon:newest?.coupon??null,statementValue:base.value,valuationBasis:projectedMaturityValue?'projectedMaturity':'statement',reconciliationNote:note,payoutDifference:sum(flows.map(f=>f.reconciliationDifference??'0')).toFixed()}});
 }
 return {holdings,redeemed};
}
