import { Decimal } from 'decimal.js';
import { parse, isLosslessNumber } from 'lossless-json';

const Money = Decimal.clone({ precision: 50 });
const iso = (date: Date) => date.toISOString().replace(/\.\d{3}Z$/, 'Z');
type Row = Record<string, unknown>;
function rows(text: string): Row[] {
  const result = parse(text) as { status?: string; data?: unknown };
  if (result.status !== 'success' || !Array.isArray(result.data)) throw new Error('Invalid Kite holdings response.');
  return result.data.map((row) => {
    if (!row || typeof row !== 'object' || Array.isArray(row)) throw new Error('Invalid Kite holding.');
    return row as Row;
  });
}
function amount(value: unknown): Decimal {
  const text = isLosslessNumber(value) ? value.value : typeof value === 'string' ? value : null;
  if (text === null) throw new Error('Missing Kite amount.');
  const decimal = new Money(text);
  if (!decimal.isFinite() || decimal.isNegative()) throw new Error('Invalid Kite amount.');
  return decimal;
}
function optionalAmount(row: Row, key: string): Decimal { return row[key] == null ? new Money(0) : amount(row[key]); }
function text(row: Row, key: string): string {
  if (typeof row[key] !== 'string' || !row[key]) throw new Error('Missing Kite instrument identifier.');
  return row[key] as string;
}

export function zerodhaSnapshot(equity: string, funds: string, at: Date) {
  const seen = new Set<string>();
  const holdings = [
    ...rows(equity).map((row) => ({ row, fund: false })),
    ...rows(funds).map((row) => ({ row, fund: true })),
  ].flatMap(({ row, fund }) => {
    const symbol = text(row, 'tradingsymbol');
    const instrumentID = fund ? `${symbol}:${row.folio ?? 'demat'}` : String(row.isin ?? `${text(row, 'exchange')}:${symbol}`);
    const id = `zerodha:${fund ? 'mf' : 'eq'}:${instrumentID}`;
    if (seen.has(id)) throw new Error('Duplicate Kite holding; import stopped to avoid double counting.');
    seen.add(id);
    if (!fund && (optionalAmount(row, 'collateral_quantity').gt(0) || optionalAmount((row.mtf as Row) ?? {}, 'quantity').gt(0))) {
      throw new Error('Pledged and margin-funded equity holdings are not supported yet.');
    }
    if (row.discrepancy === true) throw new Error('Kite reports a holding discrepancy; review the account before importing.');
    const quantity = fund ? amount(row.quantity) : amount(row.quantity).plus(optionalAmount(row, 't1_quantity')).minus(optionalAmount(row, 'used_quantity'));
    if (quantity.isNegative()) throw new Error('Invalid Kite holding quantity.');
    if (quantity.isZero()) return [];
    const invested = quantity.times(amount(row.average_price));
    const quote = optionalAmount(row, 'last_price');
    const value = quote.gt(0) ? quantity.times(quote) : null;
    const gain = value?.minus(invested) ?? null;
    const navDate = fund && typeof row.last_price_date === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(row.last_price_date)
      ? new Date(`${row.last_price_date}T00:00:00+05:30`) : null;
    return [{
      id, name: fund ? text(row, 'fund') : symbol, symbol,
      assetClass: fund ? 'mutualFund' : 'indianEquity', accountID: 'zerodha',
      quantity: quantity.toFixed(), unit: fund ? 'units' : 'shares', invested: invested.toFixed(),
      value: value?.toFixed() ?? null, gain: gain?.toFixed() ?? null,
      gainPercent: gain !== null && invested.gt(0) ? gain.div(invested).times(100).toFixed() : null,
      quote: quote.gt(0) ? quote.toFixed() : null, quoteCurrency: 'INR', fxRate: '1', fxAt: null,
      quoteAt: navDate && !isNaN(navDate.getTime()) ? iso(navDate) : null,
      source: fund ? 'Zerodha Coin via Kite Connect' : 'Zerodha Kite Connect',
      priceBasis: fund ? 'Last reported NAV; timestamp unavailable when not supplied by Kite.' : 'Last reported holding price; fetched at snapshot time, trade timestamp not supplied by Kite.',
      history: [],
    }];
  });
  const invested = holdings.reduce((sum, h) => sum.plus(h.invested), new Money(0));
  const valued = holdings.filter((h) => h.value !== null);
  const value = valued.reduce((sum, h) => sum.plus(h.value!), new Money(0));
  const covered = valued.reduce((sum, h) => sum.plus(h.invested), new Money(0));
  const gain = value.minus(covered);
  const available = holdings.length === 0 || valued.length > 0;
  return {
    id: `zerodha-${iso(at)}`, reportingCurrency: 'INR', capturedAt: iso(at), holdingsSyncAt: iso(at),
    coverage: valued.length === holdings.length ? 'complete' : valued.length ? 'partial' : 'unavailable',
    value: available ? value.toFixed() : null, invested: invested.toFixed(), coveredInvested: covered.toFixed(),
    gain: available ? gain.toFixed() : null,
    gainPercent: available && covered.gt(0) ? gain.div(covered).times(100).toFixed() : null,
    holdings,
    allocation: ['indianEquity', 'mutualFund'].flatMap((assetClass) => {
      const total = valued.filter((h) => h.assetClass === assetClass).reduce((sum, h) => sum.plus(h.value!), new Money(0));
      return total.gt(0) ? [{ assetClass, value: total.toFixed(), percent: total.div(value).times(100).toFixed() }] : [];
    }),
    history: [],
    connections: [{ id: 'zerodha', name: 'Zerodha', symbol: 'Z', status: 'connected', lastSyncAt: iso(at),
      description: 'Equity delivery holdings and Coin mutual funds. Intraday positions are excluded.' }],
  };
}
