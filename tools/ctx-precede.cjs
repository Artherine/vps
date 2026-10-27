// 找出「掉坑点」之前发生了什么：紧邻的工具调用与状态写入事件
const fs = require('fs');
const z = require('zlib');
const MAGIC = 0xFD2FB528;
function fl(b, s) {
  if (s + 4 > b.length || b.readUInt32LE(s) !== MAGIC) return -1;
  let p = s + 4; const f = b[p++];
  const fcs = (f >> 6) & 3, ss = (f >> 5) & 1, ck = (f >> 2) & 1, did = f & 3;
  if (!ss) p += 1;
  p += did === 0 ? 0 : did === 1 ? 1 : did === 2 ? 2 : 4;
  p += fcs === 0 ? (ss ? 1 : 0) : fcs === 1 ? 2 : fcs === 2 ? 4 : 8;
  for (;;) { const bh = b[p] | (b[p + 1] << 8) | (b[p + 2] << 16); p += 3;
    const last = bh & 1, t = (bh >> 1) & 3, sz = bh >>> 3;
    if (t === 0) p += sz; else if (t === 1) p += 1; else if (t === 2) p += sz; else return -1;
    if (last) break; }
  if (ck) p += 4; return p - s;
}
function* evs(file) {
  const buf = fs.readFileSync(file); let p = 0;
  while (p < buf.length) {
    const len = fl(buf, p); if (len <= 0) break;
    const txt = z.zstdDecompressSync(buf.subarray(p, p + len)).toString('utf8'); p += len;
    for (const line of txt.split('\n')) { if (!line.trim()) continue; try { yield JSON.parse(line); } catch (e) {} }
  }
}
const toolName = (ev) => {
  const d = ev.data || {};
  return d.name || d.tool || d.toolName || (d.call && (d.call.name || d.call.tool)) || (d.request && d.request.name) || '?';
};
const dt = (t) => typeof t === 'number' ? new Date(t).toISOString().replace('T', ' ').slice(5, 19) : '-';

const file = process.argv[2];
let lastTools = [], flag = { todo: 0, ws: 0, sys: 0, dev: 0, reqCtx: 0, splice: 0, catalog: 0, usermsg: 0 };
let idx = 0, missShown = 0, hitShown = 0;
const missSummary = [], hitSummary = [];
for (const ev of evs(file)) {
  if (ev.type === 'tool/call') { lastTools.push(toolName(ev)); if (lastTools.length > 6) lastTools.shift(); }
  if (ev.type === 'todo/write') flag.todo++;
  if (ev.type === 'workspace/changes') flag.ws++;
  if (ev.type === 'system/message') flag.sys++;
  if (ev.type === 'developer/message') flag.dev++;
  if (ev.type === 'request/context') flag.reqCtx++;
  if (ev.type === 'agent/inbox/spliced') flag.splice++;
  if (ev.type === 'subagent/catalog') flag.catalog++;
  if (ev.type === 'user/message') flag.usermsg++;
  const u = ev.data && ev.data.usage;
  if (u && typeof u.inputTokens === 'number') {
    idx++;
    const fresh = u.inputTokens, cached = u.cacheReadTokens || 0, prompt = fresh + cached;
    const ratio = prompt ? cached / prompt : 0;
    const f = flag, tools = lastTools.slice(-4).join(' > ');
    const line = '  ' + dt(ev.time) + '  #' + String(idx).padStart(3) + ' turn' + String(ev.data.turn).padStart(2) + '.' + ev.data.step +
      '  prompt=' + String(prompt).padStart(7) + '  命中=' + (ratio * 100).toFixed(1).padStart(5) + '%' +
      '  | 自上次请求以来: 工具=' + (tools || '无') +
      '  todo=' + f.todo + ' ws改动=' + f.ws + ' sys=' + f.sys + ' dev=' + f.dev + ' reqCtx=' + f.reqCtx + ' splice=' + f.splice + ' catalog=' + f.catalog + ' user=' + f.usermsg;
    if (ratio < 0.5 && missShown < 8) { console.log(line); missShown++; }
    missSummary.push({ ratio: ratio, todo: f.todo, ws: f.ws, sys: f.sys, dev: f.dev, reqCtx: f.reqCtx, splice: f.splice, catalog: f.catalog, r: ratio, t: ev.time });
    hitSummary.push({ ratio: ratio, todo: f.todo, ws: f.ws, sys: f.sys, dev: f.dev, reqCtx: f.reqCtx, splice: f.splice, catalog: f.catalog });
    flag = { todo: 0, ws: 0, sys: 0, dev: 0, reqCtx: 0, splice: 0, catalog: 0, usermsg: 0 };
  }
}
const avg = (a, k) => (a.reduce((s, x) => s + x[k], 0) / a.length).toFixed(2);
const misses = missSummary.filter((x) => x.ratio < 0.5);
const hits = missSummary.filter((x) => x.ratio >= 0.9);
console.log('\n--- 掉坑点 vs 命中 的「前置事件」平均次数对比 ---');
console.log('  指标            掉坑(n=' + misses.length + ')   命中(n=' + hits.length + ')');
for (const k of ['todo', 'ws', 'sys', 'dev', 'reqCtx', 'splice', 'catalog']) {
  console.log('  ' + k.padEnd(14) + avg(misses, k).padStart(6) + avg(hits, k).padStart(12));
}
