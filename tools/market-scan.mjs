import fs from 'node:fs';

const OUT = 'C:/Artherine/DSH/Temp/market.json';
const urls = [
  'https://deepseek1024.com/api/v1/plugins',
  'https://deepseek1024.com/api/v1/plugins?page=1&pageSize=500',
];

let raw = null;
for (const u of urls) {
  for (let i = 1; i <= 3 && raw === null; i++) {
    try {
      const r = await fetch(u, { signal: AbortSignal.timeout(60000) });
      console.log(`${u} -> HTTP ${r.status}`);
      if (r.ok) { raw = await r.text(); break; }
    } catch (e) {
      console.log(`${u} -> ${e.name}: ${e.message}`);
    }
    await new Promise((s) => setTimeout(s, 1500));
  }
  if (raw) break;
}

if (!raw) { console.log('catalog fetch failed'); process.exit(1); }
fs.writeFileSync(OUT, raw);
console.log(`saved ${raw.length} bytes -> ${OUT}`);

const parsed = JSON.parse(raw);
const root = parsed.snapshot ?? parsed;
const items = root.items ?? [];
console.log(`top-level keys: ${Object.keys(parsed).join(', ')}`);
console.log(`items: ${items.length}   page: ${JSON.stringify(root.page ?? null)}`);

const byCat = {};
for (const it of items) for (const c of it.categories ?? ['(none)']) byCat[c] = (byCat[c] ?? 0) + 1;
console.log('categories: ' + Object.entries(byCat).map(([k, v]) => `${k}=${v}`).join(' '));

const want = new Set(['memory', 'theme', 'ui', 'session', 'skill']);
const sel = items.filter((it) => (it.categories ?? []).some((c) => want.has(c)));
console.log(`\n--- ${sel.length} items in ${[...want].join('/')} ---`);
sel.sort((a, b) => String(b.updatedAt ?? '').localeCompare(String(a.updatedAt ?? '')));
for (const it of sel) {
  const pkg = it.package ? `${it.package.registry}:${it.package.name}` : '-';
  console.log(
    `[${(it.categories ?? []).join(',')}] ${it.name}@${it.latestVersion ?? '?'}  pkg=${pkg}  upd=${(it.updatedAt ?? '').slice(0, 10)}  pub=${it.publisher?.name ?? '?'}`
  );
  console.log(`    id=${it.id}`);
  const s = (it.summary ?? '').replace(/\s+/g, ' ');
  console.log(`    ${s.slice(0, 200)}`);
}
