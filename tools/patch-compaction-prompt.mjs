// 替换 DSH 的两处压缩相关文本：
//   1. COMPACTION_INSTRUCTION —— 摘要器被要求写什么
//   2. CHECKPOINT_PREAMBLE    —— 压缩后注入给会话的开场白
//
// 为什么要改这两处而不是写后端插件：
//   dsh-compaction-basic 只在 app bundle 里，profile 里没有，装包替换不可行。
//   该包 README 说 summarize() 是唯一的子类钩子，但那要写一个新后端插件。
// 为什么必须改两处：
//   只改指令，会话读到的开场白仍写着 "without acknowledging this checkpoint"，
//   等于把"你被压缩过"这件事继续藏起来。
//
// 代价：DSH 更新会覆盖。所以本脚本与两个 .txt 必须留在工作区，更新后重跑。
// 用法（需管理员权限，目标是 Program Files）：
//   node tools\patch-compaction-prompt.mjs            打补丁
//   node tools\patch-compaction-prompt.mjs --check    只检查
//   node tools\patch-compaction-prompt.mjs --restore  从最新备份还原
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const HERE = path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const TARGET =
  'C:/Program Files/DSH Desktop/resources/app/node_modules/@deepseek-ai/dsh-compaction-basic/lib/index.js';
const PROMPT_TXT = path.join(HERE, 'compaction-prompt.txt');
const PREAMBLE_TXT = path.join(HERE, 'compaction-preamble.txt');

const args = process.argv.slice(2);
const checkOnly = args.includes('--check');
const restore = args.includes('--restore');

if (!fs.existsSync(TARGET)) {
  console.error('找不到目标文件：' + TARGET);
  process.exit(1);
}
const dir = path.dirname(TARGET);
const base = path.basename(TARGET);
const backups = fs
  .readdirSync(dir)
  .filter((f) => f.startsWith(base + '.orig-'))
  .sort();

if (restore) {
  if (!backups.length) {
    console.error('没有可用的备份（' + base + '.orig-*）。');
    process.exit(1);
  }
  const src = backups[backups.length - 1];
  fs.copyFileSync(path.join(dir, src), TARGET);
  console.log('已从 ' + src + ' 还原。');
  process.exit(0);
}

let src = fs.readFileSync(TARGET, 'utf8');
const report = [];

// ---------- 1. COMPACTION_INSTRUCTION ----------
const M_START = 'const COMPACTION_INSTRUCTION = [';
const M_END = '].join("\\n");';
{
  const i = src.indexOf(M_START);
  if (i < 0) {
    console.error('找不到 ' + M_START + '。文件结构可能已变，未做任何修改。');
    process.exit(1);
  }
  const j = src.indexOf(M_END, i);
  if (j < 0) {
    console.error('找不到数组结尾 ' + M_END + '。未做任何修改。');
    process.exit(1);
  }
  const oldBlock = src.slice(i, j + M_END.length);
  const raw = fs
    .readFileSync(PROMPT_TXT, 'utf8')
    .replace(/\r\n/g, '\n')
    .replace(/\s+$/, '');
  const lines = raw.split('\n');
  const elems = lines.map((l) => '\t' + JSON.stringify(l)).join(',\n');
  const newBlock = M_START + '\n' + elems + '\n' + M_END;
  report.push('指令：' + oldBlock.length + ' → ' + newBlock.length + ' 字符（' + lines.length + ' 行）');
  src = src.slice(0, i) + newBlock + src.slice(j + M_END.length);
}

// ---------- 2. CHECKPOINT_PREAMBLE ----------
const P_RE = /const CHECKPOINT_PREAMBLE = "((?:[^"\\]|\\.)*)";/;
{
  const m = src.match(P_RE);
  if (!m) {
    report.push('开场白：没找到 CHECKPOINT_PREAMBLE，跳过（不影响指令替换）');
  } else {
    const oldText = JSON.parse('"' + m[1] + '"');
    const raw = fs
      .readFileSync(PREAMBLE_TXT, 'utf8')
      .replace(/\r\n/g, '\n')
      .replace(/\s+$/, '');
    const newLiteral = 'const CHECKPOINT_PREAMBLE = ' + JSON.stringify(raw) + ';';
    report.push('开场白：' + oldText.length + ' → ' + raw.length + ' 字符');
    src = src.replace(P_RE, () => newLiteral);
  }
}

console.log('=== 将要做的修改 ===');
for (const r of report) console.log('  ' + r);

// ---------- 语法检查 ----------
{
  const tmpDir = path.join(HERE, '..', 'projects', 'scratchpad', '_tmp');
  fs.mkdirSync(tmpDir, { recursive: true });
  const probe = path.join(tmpDir, 'compact-probe.mjs');
  try {
    fs.writeFileSync(probe, src, 'utf8');
    execFileSync(process.execPath, ['--check', probe], { stdio: 'ignore' });
    console.log('  语法检查：通过');
  } catch (e) {
    console.error('  语法检查：失败，未写入。');
    console.error(String(e.stderr || e.message).slice(0, 900));
    process.exit(1);
  } finally {
    try {
      fs.unlinkSync(probe);
    } catch {}
  }
}

if (checkOnly) {
  console.log('\n--check 模式，未写入。');
  process.exit(0);
}

const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
const backupName = base + '.orig-' + stamp;
try {
  fs.copyFileSync(TARGET, path.join(dir, backupName));
} catch (e) {
  console.error('备份失败（需要管理员权限）：' + e.message);
  process.exit(1);
}
try {
  fs.writeFileSync(TARGET, src, 'utf8');
} catch (e) {
  console.error('写入失败（需要管理员权限）：' + e.message);
  console.error('备份已保存为 ' + backupName);
  process.exit(1);
}
console.log('\n已写入。备份：' + backupName);
console.log('重启 DSH 后生效。回滚：node tools\\patch-compaction-prompt.mjs --restore');
