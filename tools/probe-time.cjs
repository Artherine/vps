const fs=require('fs'),z=require('zlib');
const MAGIC=0xFD2FB528;
function fl(b,s){if(s+4>b.length||b.readUInt32LE(s)!==MAGIC)return -1;let p=s+4;const f=b[p++];const fcs=(f>>6)&3,ss=(f>>5)&1,ck=(f>>2)&1,did=f&3;if(!ss)p+=1;p+=did===0?0:did===1?1:did===2?2:4;p+=fcs===0?(ss?1:0):fcs===1?2:fcs===2?4:8;for(;;){const bh=b[p]|(b[p+1]<<8)|(b[p+2]<<16);p+=3;const last=bh&1,t=(bh>>1)&3,sz=bh>>>3;if(t===0)p+=sz;else if(t===1)p+=1;else if(t===2)p+=sz;else return -1;if(last)break;}if(ck)p+=4;return p-s;}
const buf=fs.readFileSync(process.argv[2]);let p=0;const seen={};
while(p<buf.length){const len=fl(buf,p);if(len<=0)break;const txt=z.zstdDecompressSync(buf.subarray(p,p+len)).toString('utf8');p+=len;
 for(const line of txt.split('\n')){ if(!line.trim())continue; let ev; try{ev=JSON.parse(line)}catch(e){continue}
  const kind = ev.data&&ev.data.usage?'USAGE':ev.type;
  if(seen[kind])continue; seen[kind]=1;
  if(seen[kind] && (kind==='USAGE'||ev.type==='turn/start'||ev.type==='user/message'||ev.type==='assistant/message')){
    console.log('--- '+kind+' 顶层键: '+Object.keys(ev).join(','));
    if(ev.time!==undefined)console.log('    time='+ev.time+'  ('+(ev.time>1e12?'ms':'可能是秒或相对值')+')  -> '+new Date(ev.time).toISOString());
    if(ev.data)console.log('    data 键: '+Object.keys(ev.data).slice(0,12).join(',')+(ev.data.usage?'   usage='+JSON.stringify(ev.data.usage):''));
  }
 }}
