// Compatibility check: plugin package  vs  installed DSH host (unpacked resources\app).
// Checks: dsh.client.inject availability, ESM named imports, module-loader requires.
// Usage: node compat-plugins.js <hostAppDir> <pluginDir> [<pluginDir> ...]
const fs = require('fs');
const path = require('path');

const HOST = process.argv[2];
const HOST_NM = path.join(HOST, 'node_modules');
const TARGETS = process.argv.slice(3);

const memo = new Map();
const pkgDir = (pkg) => {
  const p = path.join(HOST_NM, ...pkg.split('/'));
  return fs.existsSync(path.join(p, 'package.json')) ? p : null;
};
function allJs(dir, acc = []) {
  let entries = [];
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch (e) { return acc; }
  for (const e of entries) {
    if (e.name === 'node_modules' && dir !== HOST_NM) continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) allJs(p, acc);
    else if (/\.(js|mjs|cjs)$/.test(e.name)) acc.push(p);
  }
  return acc;
}
function entryFiles(dir, pj) {
  const cands = [];
  const pick = (v) => (typeof v === 'string' ? v : v && (v.import || v.default || v.require));
  if (pj.exports) {
    const root = typeof pj.exports === 'string' ? pj.exports : (pj.exports['.'] || pj.exports);
    const got = pick(root);
    if (got) cands.push(got);
  }
  for (const k of [pj.module, pj.main, 'index.js']) if (k) cands.push(k);
  const out = [];
  for (let c of cands) {
    c = String(c).replace(/^\.\//, '');
    const f = path.join(dir, c);
    if (fs.existsSync(f) && fs.statSync(f).isFile()) out.push(f);
  }
  if (!out.length) { const ix = path.join(dir, 'index.js'); if (fs.existsSync(ix)) out.push(ix); }
  return out;
}
function collect(text, names, stars) {
  for (const m of text.matchAll(/export\s*\{([^}]*)\}/g)) {
    for (const part of m[1].split(',')) {
      const seg = part.trim(); if (!seg) continue;
      const as = seg.match(/\bas\s+([A-Za-z0-9_$]+)$/);
      const n = as ? as[1] : seg.replace(/^type\s+/, '').trim();
      if (n) names.add(n);
    }
  }
  for (const m of text.matchAll(/export\s+(?:async\s+)?(?:const|let|var|function|class)\s+([A-Za-z0-9_$]+)/g)) names.add(m[1]);
  if (/export\s+default\b/.test(text)) names.add('default');
  for (const m of text.matchAll(/export\s*\*\s*from\s*["']([^"']+)["']/g)) stars.push(m[1]);
}
function hostExports(pkg, depth = 0) {
  if (memo.has(pkg)) return memo.get(pkg);
  const dir = pkgDir(pkg);
  const res = { names: new Set(), version: '?', missingPkg: !dir, dir, externalStar: false };
  memo.set(pkg, res);
  if (!dir) return res;
  let pj = {};
  try { pj = JSON.parse(fs.readFileSync(path.join(dir, 'package.json'), 'utf8')); res.version = pj.version; } catch (e) {}
  const stars = [];
  for (const f of entryFiles(dir, pj)) collect(fs.readFileSync(f, 'utf8'), res.names, stars);
  const queue = [...stars]; let guard = 0;
  while (queue.length && guard++ < 400) {
    const spec = queue.shift();
    if (spec.startsWith('.')) {
      const base = path.join(dir, spec);
      const cand = [base, base + '.js', path.join(base, 'index.js')].find((p) => fs.existsSync(p) && fs.statSync(p).isFile());
      if (cand) { const more = []; collect(fs.readFileSync(cand, 'utf8'), res.names, more); queue.push(...more); }
    } else if (spec.startsWith('@deepseek-ai/') && depth < 3) {
      const sub = hostExports(spec, depth + 1);
      for (const n of sub.names) res.names.add(n);
      if (sub.externalStar) res.externalStar = true;
    } else res.externalStar = true;
  }
  if (!res.names.size) for (const f of allJs(dir).slice(0, 200)) collect(fs.readFileSync(f, 'utf8'), res.names, []);
  return res;
}
// does the name appear anywhere in the package (avoids false alarms on odd entry layouts)?
function nameSomewhere(pkg, name) {
  const dir = pkgDir(pkg); if (!dir) return false;
  const re = new RegExp(`\\b${name}\\b`);
  for (const f of allJs(dir).slice(0, 400)) if (re.test(fs.readFileSync(f, 'utf8'))) return true;
  return false;
}
// BUGFIX: an installed plugin normally lives under a .../node_modules/ path, so
// testing the ABSOLUTE path against /node_modules/ skipped every file and made
// the whole source scan vacuous. Match relative to the plugin root instead.
function readPluginJs(dir) {
  const root = dir.replace(/[\\/]+$/, '').length;
  return allJs(dir).filter((f) => {
    const rel = f.slice(root).replace(/\\/g, '/');
    return !/^\/(src|docs|preview|node_modules)\//.test(rel);
  });
}

for (const PLUGIN of TARGETS) {
  let pj = {};
  try { pj = JSON.parse(fs.readFileSync(path.join(PLUGIN, 'package.json'), 'utf8')); } catch (e) {}
  console.log(`\n================ ${pj.name}@${pj.version} ================`);

  // 1. declared client injects
  const injects = (pj.dsh && pj.dsh.client && pj.dsh.client.inject) || [];
  if (injects.length) {
    console.log('-- dsh.client.inject --');
    for (const spec of injects) {
      const res = hostExports(spec);
      console.log(`  ${res.missingPkg ? 'FAIL' : 'ok  '}  ${spec}${res.missingPkg ? '' : '@' + res.version}`);
    }
  }

  // 2. scan plugin sources
  const files = readPluginJs(PLUGIN);
  const esm = new Map(), req = new Map();
  for (const f of files) {
    const text = fs.readFileSync(f, 'utf8');
    for (const m of text.matchAll(/import\s*\{([^}]*)\}\s*from\s*["']([^"']+)["']/g)) {
      const names = m[1].split(',').map((s) => s.trim().split(/\s+as\s+/)[0].replace(/^type\s+/, '').trim()).filter(Boolean);
      if (!esm.has(m[2])) esm.set(m[2], new Set());
      for (const n of names) esm.get(m[2]).add(n);
    }
    const alias = new Map();
    for (const m of text.matchAll(/(?:let|const|var)\s+([A-Za-z0-9_$]+)\s*=\s*require\(\s*["']([^"']+)["']\s*\)/g)) alias.set(m[1], m[2]);
    for (const [al, spec] of alias) {
      const re = new RegExp(`\\b${al.replace(/\$/g, '\\$')}\\.([A-Za-z0-9_$]+)`, 'g');
      if (!req.has(spec)) req.set(spec, new Set());
      for (const m of text.matchAll(re)) req.get(spec).add(m[1]);
    }
    // destructured requires: const { A, B } = require("spec")
    for (const m of text.matchAll(/(?:let|const|var)\s*\{([^}]*)\}\s*=\s*require\(\s*["']([^"']+)["']\s*\)/g)) {
      if (!req.has(m[2])) req.set(m[2], new Set());
      for (const n of m[1].split(',').map((s) => s.trim().split(':').pop().trim()).filter(Boolean)) req.get(m[2]).add(n);
    }
  }

  const checkGroup = (title, map) => {
    const rows = [...map].filter(([s]) => s.startsWith('@deepseek-ai/')).sort();
    if (!rows.length) return 0;
    console.log(`-- ${title} --`);
    let bad = 0;
    for (const [spec, names] of rows) {
      const res = hostExports(spec);
      if (res.missingPkg) { console.log(`  FAIL  ${spec}: host does not ship this package`); bad++; continue; }
      const hard = [...names].filter((n) => !res.names.has(n) && !nameSomewhere(spec, n));
      const soft = [...names].filter((n) => !res.names.has(n) && nameSomewhere(spec, n));
      if (hard.length) { console.log(`  FAIL  ${spec}@${res.version}: not found -> ${hard.join(', ')}`); bad++; }
      else if (soft.length) console.log(`  warn  ${spec}@${res.version}: in sources but not entry exports -> ${soft.join(', ')}`);
      else console.log(`  ok    ${spec}@${res.version}: ${names.size} name(s)`);
    }
    return bad;
  };

  const b1 = checkGroup('ESM named imports', esm);
  const b2 = checkGroup('client requires', req);
  const b3 = injects.filter((s) => !pkgDir(s)).length;
  console.log(`RESULT: ${b1 + b2 + b3} problem(s)`);
}
