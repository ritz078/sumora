import { Decimal } from 'decimal.js';
import { istDate } from './daily-prices';
import { validDay } from './gold-prices';
const amount='([0-9]+(?:\\.[0-9]+)?)';
function date(text:string) {
 const m=/^(\d{1,2}),?\s+([A-Za-z]+),?\s+(\d{4})$/.exec(text.trim()) ?? (()=>{const v=/^([A-Za-z]+)\s+(\d{1,2}),?\s+(\d{4})$/.exec(text.trim());return v ? [v[0],v[2],v[1],v[3]] : null;})();
 if(!m)throw new Error('Missing statement date.');
 const month=['january','february','march','april','may','june','july','august','september','october','november','december'].indexOf(m[2].toLowerCase())+1;
 const result=`${m[3]}-${String(month).padStart(2,'0')}-${m[1].padStart(2,'0')}`;
 if(!month || !validDay(result))throw new Error('Invalid statement date.');return result;
}
export function parseGullakStatement(raw:string,at=new Date()) {
 const text=raw.replace(/\s+/g,' ').trim();
 if((text.match(/Monthly Statement for/g)??[]).length!==1 || !text.includes('Augmont Goldtech Private Limited'))throw new Error('Unrecognized Gullak monthly statement.');
 const period=/Period\s*:\s*(.*?)\s+-\s+(.*?)\s+Total holdings on\s+(.*?)\s+(\d+(?:\.\d+)?)\s*gm\s+(\d+(?:\.\d+)?)\s*gm/.exec(text);
 if(!period)throw new Error('Missing statement balances.');
 const periodStart=date(period[1]),periodEnd=date(period[2]),balanceDate=date(period[3]);
 if(periodStart>periodEnd || periodEnd>balanceDate || balanceDate>istDate(at))throw new Error('Invalid statement period.');
 const opening=new RegExp('Opening balance on (.*?): Gold:\\s*'+amount+'\\s*gm').exec(text);
 if(!opening || date(opening[1])!==periodStart)throw new Error('Missing opening gold balance.');
 const read=(label:string)=>{const matches=[...text.matchAll(new RegExp(label+'\\s+(?:(?:₹|INR)\\s*[0-9,.]+|-)\\s+'+amount+'\\s*gm','g'))];if(matches.length!==1)throw new Error('Missing or duplicate gold summary.');return new Decimal(matches[0][1]);};
 const buys=read('Total Buy - Gold'),sells=read('Total Sell - Gold'),interest=read('Gold\\+ Interest');
 const rewards=/Rewards - \(Gold\+Silver\)\s+(?:₹|INR)\s*([0-9,.]+)\s+-/.exec(text);
 if(!rewards || !new Decimal(rewards[1].replaceAll(',','')).isZero())throw new Error('Rewards require review before importing.');
 const grams=new Decimal(period[4]),openingGrams=new Decimal(opening[2]);
 if(!openingGrams.plus(buys).minus(sells).plus(interest).eq(grams))throw new Error('Gold summary does not reconcile.');
 return {grams:grams.toFixed(),openingGrams:openingGrams.toFixed(),periodStart,periodEnd,balanceDate};
}
