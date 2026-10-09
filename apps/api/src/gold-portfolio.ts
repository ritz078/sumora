import { GOLD_ID } from './gold-prices';
import { portfolioTotals, type Portfolio } from './portfolio-valuation';
import type { KiteEnvironment } from './zerodha';
export async function goldPortfolio(env:Pick<KiteEnvironment,'DB'>,snapshot:Portfolio,owner:string):Promise<Portfolio> {
 const checkpoint=await env.DB.prepare('SELECT * FROM gullak_checkpoints WHERE owner_id=?').bind(owner).first<{grams:string;balance_date:string;period_end:string;imported_at:number}>();
 if(!checkpoint)return snapshot;
 const holding:Portfolio['holdings'][number]={id:'gullak:gold',name:'Gullak Gold',symbol:GOLD_ID,assetClass:'gold',accountID:'gullak',quantity:checkpoint.grams,unit:'grams',invested:'0',costBasisKnown:false,
 value:null,gain:null,gainPercent:null,quote:null,quoteAt:null,quoteCurrency:'INR',fxRate:'1',fxAt:null,history:[],source:'Snapdata / IBJA daily benchmark',
 priceBasis:`Estimated benchmark value; recorded gold balance dated ${checkpoint.balance_date}, statement period ending ${checkpoint.period_end}. Leased gold is included in total grams. Acquisition cost is unavailable; this is not a Gullak sell quote.`};
 return portfolioTotals({...snapshot,holdings:[...snapshot.holdings.filter(h=>h.id!=='gullak:gold'),holding],connections:[...snapshot.connections.filter(c=>c.id!=='gullak'),{id:'gullak',name:'Gullak',symbol:'G',status:'connected',lastSyncAt:`${checkpoint.balance_date}T00:00:00Z`,description:`Recorded gold grams from monthly statement; balance dated ${checkpoint.balance_date}. Price updates daily.`}]});
}
