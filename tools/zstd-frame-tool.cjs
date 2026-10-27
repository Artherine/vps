// zstd 追加式日志工具（DSH 的 session.jsonl.zstd 是「一帧一次追加」的多帧文件）
// 用法:
//   node zstd-frame-tool.cjs info  <file>                    统计帧数/解压总字节/行数
//   node zstd-frame-tool.cjs dump  <file> <out.jsonl>        完整解压到 out
//   node zstd-frame-tool.cjs fix   <file> <out> <from> <to>  逐帧替换(仅含 token 的帧重压，其余字节原样保留)，并校验
//   node zstd-frame-tool.cjs tail  <file> [n=8]              只解压并打印末尾 n 帧的原文
//   node zstd-frame-tool.cjs usage <file> [n=8]              只解压末尾 n 帧，报出最新一次请求的上下文长度
//                                                            （contextTokens = inputTokens + cacheReadTokens）
//                                                            splitFrames 只读帧头不解压，所以这两个模式是毫秒级的。
const fs = require('fs');
const z = require('zlib');

const MAGIC = 0xFD2FB528;

function frameLength(buf, start) {
  if (start + 4 > buf.length) return -1;
  if (buf.readUInt32LE(start) !== MAGIC) return -1;
  let p = start + 4;
  const fhd = buf[p++];
  const fcsFlag = (fhd >> 6) & 3;
  const singleSegment = (fhd >> 5) & 1;
  const checksum = (fhd >> 2) & 1;
  const didFlag = fhd & 3;
  if (!singleSegment) p += 1;                 // Window_Descriptor
  p += didFlag === 0 ? 0 : didFlag === 1 ? 1 : didFlag === 2 ? 2 : 4;  // Dictionary_ID
  p += fcsFlag === 0 ? (singleSegment ? 1 : 0) : fcsFlag === 1 ? 2 : fcsFlag === 2 ? 4 : 8; // FCS
  for (;;) {
    if (p + 3 > buf.length) return -1;
    const bh = buf[p] | (buf[p + 1] << 8) | (buf[p + 2] << 16);
    p += 3;
    const last = bh & 1, type = (bh >> 1) & 3, size = bh >>> 3;
    if (type === 0) p += size;
    else if (type === 1) p += 1;
    else if (type === 2) p += size;
    else return -1;                            // Reserved
    if (last) break;
  }
  if (checksum) p += 4;
  return p - start;
}

function splitFrames(buf) {
  const frames = [];
  let p = 0;
  while (p < buf.length) {
    const len = frameLength(buf, p);
    if (len <= 0) return { frames, badAt: p };
    frames.push([p, p + len]);
    p += len;
  }
  return { frames, badAt: p === buf.length ? -1 : p };
}

function decompressAll(buf) {
  const { frames, badAt } = splitFrames(buf);
  if (badAt >= 0) throw new Error('帧解析在中途失败，偏移 ' + badAt);
  const parts = [];
  for (const [s, e] of frames) parts.push(z.zstdDecompressSync(buf.subarray(s, e)));
  return { text: Buffer.concat(parts).toString('utf8'), frames: frames.length };
}

// 只解压末尾 n 帧。splitFrames 走帧头、不解压，所以整条路径是 O(帧数) 的元数据操作。
function readTailFrames(buf, n) {
  const { frames, badAt } = splitFrames(buf);
  if (badAt >= 0) throw new Error('帧解析在中途失败，偏移 ' + badAt);
  const take = frames.slice(Math.max(0, frames.length - n));
  const parts = [];
  for (const [s, e] of take) parts.push(z.zstdDecompressSync(buf.subarray(s, e)));
  return { text: Buffer.concat(parts).toString('utf8'), frames: frames.length, taken: take.length };
}

// 从末尾往回扫，找最新一条带 usage 的 assistant/message。
// 不用 JSON.parse 整行——assistant/message 里带 stream 分块，一行可能几百 KB。
function newestUsage(text) {
  const lines = text.split('\n').filter(Boolean);
  for (let i = lines.length - 1; i >= 0; i--) {
    const line = lines[i];
    if (!line.includes('"type":"assistant/message"')) continue;
    const um = line.match(/"usage":\s*\{([^{}]*)\}/);
    if (!um) continue;
    const num = (k) => { const m = um[1].match(new RegExp('"' + k + '"\\s*:\\s*(\\d+)')); return m ? +m[1] : 0; };
    const tm = line.match(/"time":\s*(\d+)/);
    const turnM = line.match(/"turn":\s*(\d+)/);
    return {
      time: tm ? new Date(+tm[1]).toISOString() : null,
      turn: turnM ? +turnM[1] : null,
      inputTokens: num('inputTokens'),
      cacheReadTokens: num('cacheReadTokens'),
      outputTokens: num('outputTokens'),
      contextTokens: num('inputTokens') + num('cacheReadTokens'),
      lineBytes: Buffer.byteLength(line, 'utf8'),
    };
  }
  return null;
}

const [mode, file, out, from, to] = process.argv.slice(2);

if (mode === 'info') {
  const buf = fs.readFileSync(file);
  const { frames, badAt } = splitFrames(buf);
  const { text } = decompressAll(buf);
  console.log(JSON.stringify({
    file, bytes: buf.length, frameCount: frames.length, parseStoppedAt: badAt,
    decompressedBytes: Buffer.byteLength(text, 'utf8'),
    lines: text.split('\n').filter(Boolean).length,
    first: text.split('\n')[0].slice(0, 160),
    last: text.split('\n').filter(Boolean).slice(-1)[0].slice(0, 160),
  }, null, 2));
} else if (mode === 'dump') {
  const buf = fs.readFileSync(file);
  const { text, frames } = decompressAll(buf);
  fs.writeFileSync(out, text);
  console.log('帧=' + frames + '  解压字节=' + Buffer.byteLength(text, 'utf8') + '  已写入 ' + out);
} else if (mode === 'fix') {
  const buf = fs.readFileSync(file);
  const { text: original } = decompressAll(buf);
  const { frames } = splitFrames(buf);
  const outParts = [];
  let touchedFrames = 0, hits = 0;
  for (const [s, e] of frames) {
    const piece = buf.subarray(s, e);
    const txt = z.zstdDecompressSync(piece).toString('utf8');
    const n = txt.split(from).length - 1;
    if (n === 0) { outParts.push(piece); continue; }   // 未命中 -> 原字节照搬（关键：事件帧零改动）
    hits += n; touchedFrames++;
    outParts.push(z.zstdCompressSync(Buffer.from(txt.split(from).join(to), 'utf8')));
  }
  const outBuf = Buffer.concat(outParts);
  fs.writeFileSync(out, outBuf);
  const { text: after, frames: afterFrames } = decompressAll(fs.readFileSync(out));
  const expected = original.split(from).join(to);
  console.log(JSON.stringify({
    framesIn: frames.length, framesOut: afterFrames,
    touchedFrames, replacements: hits,
    bytesIn: buf.length, bytesOut: outBuf.length,
    contentMatchesExpected: after === expected,
    lines: after.split('\n').filter(Boolean).length,
  }, null, 2));
} else if (mode === 'tail' || mode === 'usage') {
  const n = Math.max(1, parseInt(from || '8', 10) || 8);
  const buf = fs.readFileSync(file);
  const t0 = process.hrtime.bigint();
  const { text, frames, taken } = readTailFrames(buf, n);
  const ms = Number(process.hrtime.bigint() - t0) / 1e6;
  if (mode === 'tail') {
    const lines = text.split('\n').filter(Boolean);
    console.log('帧=' + frames + '  只解了末尾 ' + taken + ' 帧  耗时=' + ms.toFixed(1) + 'ms');
    for (const l of lines.slice(-n)) console.log(l.slice(0, 400));
  } else {
    const u = newestUsage(text);
    console.log(JSON.stringify({
      file, fileBytes: buf.length, frameCount: frames, framesDecoded: taken,
      elapsedMs: +ms.toFixed(1),
      newest: u,
      note: u ? 'contextTokens 就是当前上下文长度' : '末尾 ' + taken + ' 帧里没找到 assistant/message，加大 n',
    }, null, 2));
  }
} else {
  console.log('usage: info|dump|fix|tail|usage');
  process.exit(1);
}
