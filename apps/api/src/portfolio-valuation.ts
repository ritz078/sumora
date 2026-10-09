import { Decimal } from 'decimal.js';
import { priceTime, type MarketPrice } from './daily-prices';
import type { zerodhaSnapshot } from './zerodha-portfolio';

export type Portfolio = ReturnType<typeof zerodhaSnapshot>;
const Money = Decimal.clone({ precision: 50 });
export function holdingISIN(h: Portfolio['holdings'][number]) {
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
    return { ...h, quote: p.price, quoteAt: new Date(priceTime(p)).toISOString().replace('.000Z', 'Z'), value: value.toFixed(), gain: gain.toFixed(),
      gainPercent: invested.gt(0) ? gain.div(invested).times(100).toFixed() : null, source: p.source,
      priceBasis: `Closing valuation for ${p.date}; recorded quantities last synced ${original.holdingsSyncAt}.` };
  });
  if (!changed) return original;
  const valued = holdings.filter(h => h.value !== null);
  const value = valued.reduce((s,h) => s.plus(h.value!), new Money(0));
  const covered = valued.reduce((s,h) => s.plus(h.invested), new Money(0));
  const gain = value.minus(covered);
  const capturedAt = new Date(Math.max(Date.parse(original.capturedAt), ...holdings.map(h => Date.parse(h.quoteAt ?? original.capturedAt)))).toISOString().replace('.000Z', 'Z');
  return { ...original, capturedAt, id: `zerodha-${capturedAt}`, holdings, value: value.toFixed(), coveredInvested: covered.toFixed(), gain: gain.toFixed(),
    gainPercent: covered.gt(0) ? gain.div(covered).times(100).toFixed() : null,
    coverage: valued.length === holdings.length ? 'complete' : valued.length ? 'partial' : 'unavailable',
    allocation: ['indianEquity','mutualFund'].flatMap(assetClass => {
      const total = valued.filter(h => h.assetClass === assetClass).reduce((s,h) => s.plus(h.value!), new Money(0));
      return total.gt(0) ? [{ assetClass, value: total.toFixed(), percent: total.div(value).times(100).toFixed() }] : [];
    }) };
}
