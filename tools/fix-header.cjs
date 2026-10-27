// fix-header.cjs —— 只重压第 0 帧（会话 header），其余帧逐字节原样拷贝
//
// 用法: node fix-header.cjs <src> <out> <from> <to> [--no-checksum]
//
// 为什么不用 tools\zstd-frame-tool.cjs 的 fix：
//   那个是「凡含 token 的帧就重压」，会把历史正文里出现的路径也一起改掉。
//   上次迁移共替换 1,223 处，其中只有 header 的 1 处算元数据；
//   代价是 checksum 位被丢掉（1→0），属于静默的完整性降级。
//
// 本脚本的边界：
//   **只改第 0 帧的第一行**（会话 header 的 cwd），其余帧原样拼回。
//   header 里是"这个会话属于哪个 cwd"，改它是对归属的修正，不是改历史。
//
// 自检：写完立刻重新解压两份，逐行比对——除第 0 行外必须完全相同。

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
  if (!singleSegment) p += 1;
  p += didFlag === 0 ? 0 : didFlag === 1 ? 1 : didFlag === 2 ? 2 : 4;
  p += fcsFlag === 0 ? (singleSegment ? 1 : 0) : fcsFlag === 1 ? 2 : fcsFlag === 2 ? 4 : 8;
  for (;;) {
    if (p + 3 > buf.length) return -1;
    const bh = buf[p] | (buf[p + 1] << 8) | (buf[p + 2] << 16);
    p += 3;
    const last = bh & 1, type = (bh >> 1) & 3, size = bh >>> 3;
    if (type === 0) p += size;
    else if (type === 1) p += 1;
    else if (type === 2) p += size;
    else return -1;
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
  if (badAt >= 0) throw new Error('帧解析中途失败 @ ' + badAt);
  return Buffer.concat(frames.map(([s, e]) => z.zstdDecompressSync(buf.subarray(s, e)))).toString('utf8');
}

// ---- 入口 ----
const argv = process.argv.slice(2);
const noChecksum = argv.includes('--no-checksum');
const [src, out, from, to] = argv.filter(a => !a.startsWith('--'));

if (!src || !out || !from || !to) {
  console.error('用法: node fix-header.cjs <src> <out> <from> <to> [--no-checksum]');
  process.exit(2);
}

const buf = fs.readFileSync(src);
const { frames, badAt } = splitFrames(buf);
if (badAt >= 0) { console.error('帧解析失败 @ ' + badAt); process.exit(1); }

const [s0, e0] = frames[0];
const headTxt = z.zstdDecompressSync(buf.subarray(s0, e0)).toString('utf8');
const headLines = headTxt.split('\n');
const firstLine = headLines[0];
// 日志里每一行都是 JSON，反斜杠已转义（C:\some\path 在文件里存成 C:\\some\\path）。
// 所以参数收**原始 OS 路径**，这里统一转成转义形式再搜——否则永远 0 命中。
const esc = s => s.replace(/\\/g, '\\\\');
const fromEsc = esc(from), toEsc = esc(to);
const hits = firstLine.split(fromEsc).length - 1;

if (hits !== 1) {
  console.error(`拒绝执行：第 0 行里 "${from}" 出现 ${hits} 次（期望恰好 1 次）。`);
  console.error('第一行前 200 字符: ' + firstLine.slice(0, 200));
  process.exit(1);
}

const newFirst = firstLine.split(fromEsc).join(toEsc);
const newHeadTxt = [newFirst, ...headLines.slice(1)].join('\n');

// 尝试保留 checksum（上次迁移在这上面降级了完整性）
let newFrame0;
let checksumKept = false;
if (!noChecksum) {
  try {
    const c = z.constants;
    newFrame0 = z.zstdCompressSync(Buffer.from(newHeadTxt, 'utf8'), {
      params: { [c.ZSTD_c_checksumFlag]: 1 },
    });
    const fhd0 = newFrame0[4];
    checksumKept = ((fhd0 >> 2) & 1) === 1;
  } catch (e) {
    console.error('带 checksum 压缩失败，退回默认: ' + e.message);
    newFrame0 = null;
  }
}
if (!newFrame0) newFrame0 = z.zstdCompressSync(Buffer.from(newHeadTxt, 'utf8'));

// 帧 1..N 原样拷贝
const parts = [newFrame0];
for (let i = 1; i < frames.length; i++) {
  const [s, e] = frames[i];
  parts.push(buf.subarray(s, e));
}
const outBuf = Buffer.concat(parts);
fs.writeFileSync(out, outBuf);

// ---- 自检：逐行比对 ----
const beforeTxt = decompressAll(buf);
const afterTxt = decompressAll(fs.readFileSync(out));
const bLines = beforeTxt.split('\n');
const aLines = afterTxt.split('\n');

let diffIndex = -1;
if (bLines.length !== aLines.length) diffIndex = -2;
else {
  for (let i = 0; i < bLines.length; i++) {
    if (bLines[i] !== aLines[i]) { diffIndex = i; break; }
  }
}

const report = {
  源文件: src,
  输出: out,
  帧数: frames.length,
  源字节: buf.length,
  新字节: outBuf.length,
  字节差: outBuf.length - buf.length,
  第0帧压缩: `${e0 - s0} → ${newFrame0.length}`,
  header行数: headLines.length,
  header解压字节: `${Buffer.byteLength(headTxt)} → ${Buffer.byteLength(newHeadTxt)}`,
  cwd替换处数: hits,
  checksum保留: checksumKept,
  行数: `${bLines.length} → ${aLines.length}`,
  首个不同行: diffIndex,
  自检: diffIndex === 0 ? '通过（只有第 0 行变了）' : diffIndex < 0 ? '失败：行数不符' : `失败：第 ${diffIndex} 行也变了`,
};
console.log(JSON.stringify(report, null, 2));
process.exit(diffIndex === 0 ? 0 : 1);
