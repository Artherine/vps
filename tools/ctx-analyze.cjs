// 会话日志分析：先探形状，再算缓存命中与压缩事件
// 用法: node ctx-analyze.cjs shape   <log.zstd>
//       node ctx-analyze.cjs analyze <log.zstd>
const fs = require('fs');
const z = require('zlib');
const MAGIC = 0xFD2FB528;

function frameLength(buf, start) {
  if (start + 4 > buf.length) return -1;
  if (buf.readUInt32LE(start) !== MAGIC) return -1;
  let p = start + 4;
  const fhd = buf[p++];
  const fcsFlag = (fhd >> 6) & 3, singleSegment = (fhd >> 5) & 1, checksum = (fhd >> 2) & 1, didFlag = fhd & 3;
  if (!singleSegment) p += 1;
  p += didFlag === 0 ? 0 : didFlag === 1 ? 1 : didFlag === 2 ? 2 : 4;
  p += fcsFlag === 0 ? (singleSegment ? 1 : 0) : fcsFlag === 1 ? 2 : fcsFlag === 2 ? 4 : 8;
  for (;;) {
    if (p + 3 > buf.length) return -1;
    const bh = buf[p] | (buf[p + 1] << 8) | (buf[p + 2] << 16);
    p += 3;
    const last = bh & 1, type = (bh >> 1) & 3, size = bh >>> 3;
    if (type === 0) p += size; else if (type === 1) p += 1; else if (type === 2) p += size; else return -1;
    if (last) break;
  }
  if (checksum) p += 4;
  return p - start;
}

function* events(file) {
  const buf = fs.readFileSync(file);
  let p = 0, n = 0;
  while (p < buf.length) {
    const len = frameLength(buf, p);
    if (len <= 0) { console.error('帧解析在偏移 ' + p + ' 停止（未完成的尾帧）'); break; }
    const txt = z.zstdDecompressSync(buf.subarray(p, p + len)).toString('utf8');
    p += len; n++;
    for (const line of txt.split('\n')) {
      if (!line.trim()) continue;
      try { yield JSON.parse(line); } catch (e) { /* 跳过不完整行 */ }
    }
  }
  console.error('解析帧数: ' + n + '  文件字节: ' + buf.length);
}

function walkPaths(obj, prefix, out, depth) {
  if (obj === null || typeof obj !== 'object' || depth > 6) return;
  for (const [k, v] of Object.entries(obj)) {
    const path = prefix ? prefix + '.' + k : k;
    if (/cache|token|usage|context/i.test(k)) {
      const isNum = typeof v === 'number';
      out.set(path, (out.get(path) || { count: 0, num: 0, sample: '' }));
      const rec = out.get(path);
      rec.count++;
      if (isNum) rec.num++;
      if (!rec.sample) rec.sample = JSON.stringify(v).slice(0, 90);
    }
    walkPaths(v, path, out, depth + 1);
  }
}

const [mode, file] = process.argv.slice(2);

if (mode === 'shape') {
  const types = new Map(), paths = new Map();
  let lines = 0, first = null;
  for (const ev of events(file)) {
    lines++;
    if (!first) first = ev;
    types.set(ev.type, (types.get(ev.type) || 0) + 1);
    walkPaths(ev, '', paths, 0);
  }
  console.log('事件总数: ' + lines);
  console.log('\n--- 事件类型 top 40 ---');
  [...types.entries()].sort((a, b) => b[1] - a[1]).slice(0, 40).forEach(([t, c]) => console.log('  ' + String(c).padStart(6) + '  ' + t));
  console.log('\n--- 含 cache/token/usage/context 的字段路径 top 35（count/其中数值型）---');
  [...paths.entries()].sort((a, b) => b[1].count - a[1].count).slice(0, 35)
    .forEach(([k, v]) => console.log('  ' + String(v.count).padStart(6) + '/' + String(v.num).padStart(6) + '  ' + k + '   e.g. ' + v.sample));
  console.log('\n--- 第一条事件 ---');
  console.log('  ' + JSON.stringify(first).slice(0, 400));
} else if (mode === 'analyze') {
  const rows = [];
  let compactions = 0;
  for (const ev of events(file)) {
    if (/compact/i.test(String(ev.type))) compactions++;
    const u = ev.data && ev.data.usage;
    if (u && typeof u.inputTokens === 'number') {
      const fresh = u.inputTokens, cached = u.cacheReadTokens || 0, prompt = fresh + cached;
      rows.push({
        turn: ev.data.turn, step: ev.data.step, time: ev.time, fresh: fresh, cached: cached,
        prompt: prompt, out: u.outputTokens || 0, reason: u.reasoningTokens || 0,
        ratio: prompt ? cached / prompt : 0,
      });
    }
  }
  if (!rows.length) { console.log('没有解析到带 usage 的事件'); process.exit(0); }

  const ordered = rows.every((r, i) => i === 0 || (typeof r.time === 'number' && typeof rows[i - 1].time === 'number' && r.time >= rows[i - 1].time));
  const fmt = (n) => n.toLocaleString('en-US');
  const dt = (t) => typeof t === 'number' ? new Date(t).toISOString().replace('T', ' ').slice(5, 19) : '-';
  const gap = (r, i) => (i === 0 || typeof r.time !== 'number' || typeof rows[i - 1].time !== 'number') ? null : (r.time - rows[i - 1].time);

  const sum = (k) => rows.reduce((a, r) => a + r[k], 0);
  const totFresh = sum('fresh'), totCached = sum('cached');
  console.log('请求数(带usage): ' + rows.length + '   轮数: ' + new Set(rows.map((r) => r.turn)).size + '   压缩事件: ' + compactions);
  console.log('日志按时间有序: ' + ordered);
  console.log('累计未命中输入: ' + fmt(totFresh));
  console.log('累计命中输入  : ' + fmt(totCached));
  console.log('整体命中率    : ' + ((totCached / (totFresh + totCached)) * 100).toFixed(2) + '%');
  console.log('输出 tokens   : ' + fmt(sum('out')) + '（含推理 ' + fmt(sum('reason')) + '）');
  console.log('上下文峰值    : ' + fmt(Math.max(...rows.map((r) => r.prompt))) + '（最后 ' + fmt(rows[rows.length - 1].prompt) + '）');

  const buckets = { '0-10%': 0, '10-50%': 0, '50-90%': 0, '90-100%': 0 };
  for (const r of rows) { const p = r.ratio * 100; if (p < 10) buckets['0-10%']++; else if (p < 50) buckets['10-50%']++; else if (p < 90) buckets['50-90%']++; else buckets['90-100%']++; }
  console.log('命中率分布    : ' + Object.entries(buckets).map(([k, v]) => k + '=' + v).join('  '));

  const miss = [];
  rows.forEach((r, i) => { if (r.ratio < 0.5) miss.push({ r: r, i: i, g: gap(r, i) }); });
  console.log('\n--- 掉坑点（命中率<50%）与「距上次请求的间隔」---');
  let missPrompt = 0;
  for (const m of miss) {
    missPrompt += m.r.prompt;
    console.log('  ' + dt(m.r.time) + '  turn' + String(m.r.turn).padStart(2) + '.' + m.r.step +
      '  prompt=' + String(fmt(m.r.prompt)).padStart(9) + '  命中=' + (m.r.ratio * 100).toFixed(1).padStart(5) + '%' +
      '  间隔=' + (m.g === null ? '首条' : (m.g / 60000).toFixed(1) + '分'));
  }
  console.log('  合计重算 ' + fmt(missPrompt) + ' tokens = 全部输入的 ' + ((missPrompt / (totFresh + totCached)) * 100).toFixed(2) + '%');

  const withGap = rows.map((r, i) => ({ r: r, g: gap(r, i) })).filter((x) => x.g !== null && x.g > 0);
  const hitGaps = withGap.filter((x) => x.r.ratio >= 0.9).map((x) => x.g).sort((a, b) => a - b);
  const missGaps = withGap.filter((x) => x.r.ratio < 0.5).map((x) => x.g).sort((a, b) => a - b);
  const med = (a) => a.length ? a[Math.floor(a.length / 2)] : null;
  const pct = (a, p) => a.length ? a[Math.min(a.length - 1, Math.floor(a.length * p))] : null;
  console.log('\n--- 间隔统计（毫秒 -> 分钟）---');
  console.log('  命中(>=90%) 的间隔: 中位 ' + (med(hitGaps) / 60000).toFixed(1) + ' 分   90分位 ' + (pct(hitGaps, 0.9) / 60000).toFixed(1) + ' 分   最大 ' + (Math.max(...hitGaps) / 60000).toFixed(1) + ' 分');
  if (missGaps.length) console.log('  掉坑(<50%) 的间隔: 中位 ' + (med(missGaps) / 60000).toFixed(1) + ' 分   最小 ' + (Math.min(...missGaps) / 60000).toFixed(1) + ' 分   最大 ' + (Math.max(...missGaps) / 60000).toFixed(1) + ' 分');

  console.log('\n--- 最大的 8 个间隔（看是否都伴随掉坑）---');
  withGap.slice().sort((a, b) => b.g - a.g).slice(0, 8).forEach((x) => {
    console.log('  ' + dt(x.r.time) + '  间隔=' + (x.g / 60000).toFixed(0).padStart(5) + '分  prompt=' + String(fmt(x.r.prompt)).padStart(9) + '  命中=' + (x.r.ratio * 100).toFixed(1) + '%');
  });

  console.log('\n--- 逐轮末步 ---');
  const byTurn = new Map();
  for (const r of rows) byTurn.set(r.turn, r);
  [...byTurn.entries()].forEach(([t, r]) => console.log('  turn' + String(t).padStart(2) + '  ' + dt(r.time) + '  prompt=' + String(fmt(r.prompt)).padStart(9) + '  命中=' + (r.ratio * 100).toFixed(1).padStart(5) + '%'));
} else {
  console.log('usage: shape|analyze <log>');
}
