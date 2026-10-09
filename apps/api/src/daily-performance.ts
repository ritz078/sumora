import { Decimal } from 'decimal.js';
import { istDate, type MarketPrice } from './daily-prices';
import { holdingISIN, type Portfolio } from './portfolio-valuation';

const Money = Decimal.clone({ precision: 50 });
export function dailyPerformance(snapshot: Portfolio, baselines: MarketPrice[], day: string) {
  const byISIN = new Map(baselines.map(p => [`${p.kind}:${p.isin}`, p]));
  let total = new Money(0), startingValue = new Money(0), covered = 0;
  const holdings = snapshot.holdings.map(h => {
    const baseline = byISIN.get(`${h.assetClass}:${holdingISIN(h)}`);
    const quoteDay = istDate(new Date(h.quoteAt ?? snapshot.capturedAt));
    // A carried-forward quote is usable only if it is the baseline itself.
    // Quotes from an older session must not manufacture a loss against a newer close.
    const usable = baseline && h.quote !== null && quoteDay <= day && quoteDay >= baseline.date
      && (quoteDay === day || new Money(h.quote).eq(baseline.price));
    const gain = usable ? new Money(h.quantity).times(new Money(h.quote!).minus(baseline.price)) : null;
    const start = usable ? new Money(h.quantity).times(baseline.price) : null;
    if (gain && start) { total = total.plus(gain); startingValue = startingValue.plus(start); covered++; }
    return { ...h, dailyGain: gain?.toFixed() ?? null,
      dailyGainPercent: gain && start?.gt(0) ? gain.div(start).times(100).toFixed() : null,
      dailyBaselinePrice: baseline?.price ?? null, dailyBaselinePriceDate: baseline?.date ?? null };
  });
  const complete = covered === holdings.length && holdings.length > 0;
  return { ...snapshot, holdings, dailyBaselineDate: day,
    dailyGain: complete ? total.toFixed() : null,
    dailyGainPercent: complete && startingValue.gt(0) ? total.div(startingValue).times(100).toFixed() : null };
}
