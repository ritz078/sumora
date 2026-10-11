import type {PropertyEntry} from './properties';
import { Decimal } from 'decimal.js';
import { priceTime, type MarketPrice } from './daily-prices';
import type { zerodhaSnapshot } from './zerodha-portfolio';

type BrokerPortfolio = ReturnType<typeof zerodhaSnapshot>;
export type NPSSummary = {tier:string;value:string;invested:string;gain:string;xirr:string|null};
export type Portfolio = {npsSummaries?:NPSSummary[];costBasisKnown?:boolean} & Omit<BrokerPortfolio, 'holdings' | 'connections'> & { connections: (Omit<BrokerPortfolio['connections'][number], 'lastSyncAt'> & {lastSyncAt:string|null})[]; holdings: (BrokerPortfolio['holdings'][number] & { valueUSD?:string|null;investedUSD?:string|null;gainUSD?:string|null;gainPercentUSD?:string|null;costBasisKnown?: boolean; quoteTimestampIsRetrieval?:boolean; propertyTerms?:PropertyEntry; bondTerms?: {coupon:string|null;maturesOn:string|null;redemptionCheck:boolean;investedAmount?:string|null;accruedAtPurchase?:string|null;interestGross?:string;interestNet?:string;tds?:string;principalReceived?:string;nextPayout?:string|null;frequency?:string|null;repayment?:string|null;quotedCoupon?:string|null;ytm?:string|null;projectedMaturityValue?:string|null;projectionUsesOrderDate?:boolean;statementValue?:string;valuationBasis?:string;reconciliationNote?:string|null;payoutDifference?:string}; depositTerms?: {originalPrincipal:string;currentAmount:string;maturityAmount:string;rate:string;openedOn:string;maturesOn:string;lien:string} })[] };
const Money = Decimal.clone({ precision: 50 });
export function holdingISIN(h: Portfolio['holdings'][number]) {
  if (h.assetClass === 'fixedDeposit' || h.assetClass === 'bond' || h.assetClass === 'realEstate') return null;
  if (h.assetClass === 'gold') return h.symbol;
  const isin = h.assetClass === 'mutualFund' ? h.symbol : h.id.replace(/^zerodha:eq:/, '');
  return /^[A-Z]{2}[A-Z0-9]{9}[0-9]$/.test(isin) ? isin : null;
}
export function revalue(original: Portfolio, prices: MarketPrice[]): Portfolio {
  const byISIN = new Map(prices.map(p => [`${p.kind}:${p.isin}`, p]));
  let changed = false;
  const holdings = original.holdings.map(h => {
    const p = byISIN.get(`${h.assetClass}:${holdingISIN(h)}`);
    const previousAt = h.quoteAt ?? original.capturedAt;
    if (!p || h.quote !== null && Date.parse(priceTime(p)) <= Date.parse(previousAt)) {
      return { ...h, quoteAt: h.quote !== null ? previousAt : h.quoteAt };
    }
    const value = new Money(h.quantity).times(p.price), invested = new Money(h.invested), gain = value.minus(invested);
    changed = true;
    return { ...h, quoteTimestampIsRetrieval: false, quote: p.price, quoteAt: new Date(priceTime(p)).toISOString().replace('.000Z', 'Z'), value: value.toFixed(), gain: h.costBasisKnown === false ? null : gain.toFixed(),
      gainPercent: h.costBasisKnown !== false && invested.gt(0) ? gain.div(invested).times(100).toFixed() : null, source: p.source,
      priceBasis: h.assetClass === 'gold' ? `${h.priceBasis} Price date ${p.date}.` : `Closing valuation for ${p.date}; recorded quantities last synced ${original.holdingsSyncAt}.` };
  });
  if (!changed) return original;
  return portfolioTotals({ ...original, holdings });
}
export function portfolioTotals(snapshot: Portfolio): Portfolio {
  const holdings=snapshot.holdings;
  const valued = holdings.filter(h => h.value !== null);
  const value = valued.reduce((s,h) => s.plus(h.value!), new Money(0));
  const summaries=(snapshot.npsSummaries??[]).filter(n=>valued.some(h=>h.id.startsWith(`nps:${n.tier}:`)));
 const summarized=(h:Portfolio['holdings'][number])=>h.assetClass==='nps' && summaries.some(n=>h.id.startsWith(`nps:${n.tier}:`));
 const npsInvested=summaries.reduce((s,n)=>s.plus(n.invested),new Money(0));
 const invested=holdings.filter(h=>!summarized(h)).reduce((s,h)=>s.plus(h.invested),npsInvested);
  const covered = valued.filter(h=>!summarized(h) && h.costBasisKnown!==false).reduce((s,h) => s.plus(h.invested), npsInvested);
  const costKnown=valued.every(h=>h.costBasisKnown!==false || summarized(h));
  const gain = value.minus(covered);
  const available=holdings.length===0 || valued.length>0;
  const capturedAt = new Date(Math.max(Date.parse(snapshot.capturedAt), ...holdings.map(h => Date.parse(h.quoteAt ?? snapshot.capturedAt)))).toISOString().replace('.000Z', 'Z');
  return { ...snapshot, costBasisKnown:costKnown, capturedAt, id: `portfolio-${capturedAt}`, value: available ? value.toFixed() : null, invested:invested.toFixed(), coveredInvested: covered.toFixed(), gain: available && costKnown ? gain.toFixed() : null,
    gainPercent: available && costKnown && covered.gt(0) ? gain.div(covered).times(100).toFixed() : null,
    coverage: valued.length === holdings.length ? 'complete' : valued.length ? 'partial' : 'unavailable',
    allocation: ['indianEquity','usEquity','mutualFund','gold','fixedDeposit','nps','bond','realEstate'].flatMap(assetClass => {
      const total = valued.filter(h => h.assetClass === assetClass).reduce((s,h) => s.plus(h.value!), new Money(0));
      return total.gt(0) ? [{ assetClass, value: total.toFixed(), percent: total.div(value).times(100).toFixed() }] : [];
    }) };
}
