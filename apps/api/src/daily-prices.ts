import { Decimal } from 'decimal.js';

export type MarketPrice = { isin: string; kind: 'indianEquity' | 'mutualFund'; price: string; date: string; source: string };
export const istDate = (at: Date) => new Date(at.getTime() + 330 * 60000).toISOString().slice(0, 10);
export const priceTime = (p: MarketPrice) => `${p.date}T${p.kind === 'indianEquity' ? '15:30' : '23:59'}:00+05:30`;

// CSV supports quoted commas, escaped quotes and CRLF; feeds are bounded before parsing.
function records(text: string, separator: string, wanted?: ReadonlySet<string>): string[][] {
  if (wanted) {
    // Official bulk feeds use one record per line. Select candidate records before
    // decoding all cells/decimals; final matching below still requires exact ISINs.
    const identifiers = [...wanted].filter(isin => /^[A-Z]{2}[A-Z0-9]{9}[0-9]$/.test(isin));
    const firstLine = text.indexOf('\n');
    const header = firstLine < 0 ? text : text.slice(0, firstLine);
    const candidates = identifiers.length ? text.slice(firstLine + 1).match(new RegExp(`^[^\\r\\n]*(?:${identifiers.join('|')})[^\\r\\n]*$`, 'gm')) ?? [] : [];
    text = [header, ...candidates].join('\n');
  }
  const result: string[][] = []; let row: string[] = [], cell = '', quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (c === '"') { if (quoted && text[i + 1] === '"') { cell += '"'; i++; } else quoted = !quoted; }
    else if (!quoted && (c === separator || c === '\n')) {
      row.push(cell.trim()); cell = '';
      if (c === '\n') { result.push(row); row = []; }
    } else cell += c;
  }
  if (quoted) throw new Error('Invalid quoted price feed.');
  if (cell || row.length) { row.push(cell.trim()); result.push(row); }
  return result;
}
function validDate(value: string) {
  return /^\d{4}-\d{2}-\d{2}$/.test(value) && Number.isFinite(Date.parse(`${value}T00:00:00Z`)) && new Date(`${value}T00:00:00Z`).toISOString().slice(0, 10) === value;
}
function navDate(value: string) {
  const match = /^(\d{2})-([A-Za-z]{3})-(\d{4})$/.exec(value);
  if (!match) return '';
  const month = ['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'].indexOf(match[2].toLowerCase()) + 1;
  return month ? `${match[3]}-${String(month).padStart(2, '0')}-${match[1]}` : '';
}
function prices(rows: { isin: string; price: string; date: string }[], kind: MarketPrice['kind'], source: string, maxDate: string): MarketPrice[] {
  const found = new Map<string, MarketPrice>(); const ambiguous = new Set<string>();
  for (const row of rows) {
    if (!/^[A-Z]{2}[A-Z0-9]{9}[0-9]$/.test(row.isin) || !validDate(row.date) || row.date > maxDate || !/^\d+(?:\.\d+)?$/.test(row.price)) continue;
    const amount = new Decimal(row.price);
    if (!amount.isFinite() || amount.lte(0)) continue;
    const quote = { ...row, price: amount.toFixed(), kind, source };
    const previous = found.get(row.isin);
    if (previous && (previous.price !== quote.price || previous.date !== quote.date)) ambiguous.add(row.isin);
    else found.set(row.isin, quote);
  }
  return [...found.values()].filter(p => !ambiguous.has(p.isin));
}
export function parseNSE(text: string, maxDate: string, wanted?: ReadonlySet<string>): MarketPrice[] {
  const [header, ...rows] = records(text.replace(/^\uFEFF/, ''), ',', wanted);
  const col = (name: string) => { const index = header?.indexOf(name) ?? -1; if (index < 0) throw new Error(`Missing NSE column ${name}.`); return index; };
  const isin = col('ISIN'), price = col('ClsPric'), date = col('TradDt');
  return prices(rows.map(r => ({ isin: r[isin] ?? '', price: r[price] ?? '', date: r[date] ?? '' })), 'indianEquity', 'NSE daily close', maxDate).filter(p => !wanted || wanted.has(p.isin));
}
export function parseAMFI(text: string, maxDate: string, wanted?: ReadonlySet<string>): MarketPrice[] {
  const [header, ...rows] = records(text.replace(/^\uFEFF/, ''), ';', wanted);
  const col = (name: string) => { const index = header?.indexOf(name) ?? -1; if (index < 0) throw new Error(`Missing AMFI column ${name}.`); return index; };
  const payout = col('ISIN Div Payout/ ISIN Growth'), reinvest = col('ISIN Div Reinvestment'), price = col('Net Asset Value'), date = col('Date');
  return prices(rows.flatMap(r => [r[payout], r[reinvest]].map(isin => ({ isin: isin ?? '', price: r[price] ?? '', date: navDate(r[date] ?? '') }))), 'mutualFund', 'AMFI daily NAV', maxDate).filter(p => !wanted || wanted.has(p.isin));
}
