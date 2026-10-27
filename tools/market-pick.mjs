import fs from 'node:fs';

const j = JSON.parse(fs.readFileSync('C:/Artherine/DSH/Temp/market.json', 'utf8'));
const pkgs = j.packages ?? [];

// learn the install shape once
const sample = pkgs.find((p) => p.category === 'memory');
console.log('install field sample: ' + JSON.stringify(sample?.install));
console.log('installMethods sample: ' + JSON.stringify(sample?.installMethods).slice(0, 400));
console.log('');

function pkgName(p) {
  const i = p.install;
  if (typeof i === 'string') return i;
  if (i && typeof i === 'object') return i.package ?? i.npm ?? i.spec ?? JSON.stringify(i).slice(0, 60);
  return '-';
}

function show(cat, n) {
  const rows = pkgs.filter((p) => p.category === cat).sort((a, b) => (b.installCount ?? 0) - (a.installCount ?? 0)).slice(0, n);
  console.log(`========== ${cat}: top ${rows.length} of ${pkgs.filter((p) => p.category === cat).length} ==========`);
  for (const p of rows) {
    console.log(`${String(p.installCount ?? 0).padStart(5)} installs | 30d=${String(p.installs30d ?? 0).padStart(4)} | npm7d=${String(p.npmDownloads7d ?? 0).padStart(6)} | fail=${String(p.failureCount ?? 0).padStart(3)} | upd=${(p.updatedAt ?? '').slice(0, 10)} | stars=${p.stars ?? 0}`);
    console.log(`   ${p.name}  (${p.owner})  pkg=${pkgName(p)}`);
    console.log(`   ${p.url}`);
    const d = typeof p.description === 'string' ? p.description : (p.description?.zh ?? p.description?.en ?? '');
    console.log(`   ${String(d).replace(/\s+/g, ' ').slice(0, 190)}`);
    console.log('');
  }
}

show('memory', 14);
show('theme', 14);
