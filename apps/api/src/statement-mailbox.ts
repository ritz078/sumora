import {extractText,getDocumentProxy} from 'unpdf';
import {APIError} from './zerodha';
import {boundedJSON} from './gold-prices';
export async function extractStatementPDF(bytes:Uint8Array,password:string,maxPages=40,maxText=500000) {
 if(bytes.length>2*1024*1024 || new TextDecoder().decode(bytes.subarray(0,5))!=='%PDF-')throw new Error('Invalid PDF.');
 const pdf=await getDocumentProxy(bytes,{password,verbosity:0,useSystemFonts:false,disableFontFace:true});
 try{if(pdf.numPages>maxPages)throw new Error('Statement too long.');const {text}=await extractText(pdf,{mergePages:true});if(text.length>maxText)throw new Error('Statement too long.');return text;}finally{await pdf.loadingTask.destroy();}
}
export async function gmailJSON(fetcher:typeof fetch,url:string,init:RequestInit={}) {
 const response=await fetcher(url,{...init,signal:AbortSignal.timeout(15000),redirect:'manual'});
 if(response.status===401 || response.status===400 && url.includes('oauth2'))throw new APIError(409,'GMAIL_RECONNECT_REQUIRED','Reconnect Gmail to import statements.');
 return boundedJSON(response,4*1024*1024);
}
