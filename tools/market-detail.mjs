import fs from 'node:fs';

const j = JSON.parse(fs.readFileSync('C:/Artherine/DSH/Temp/market.json', 'utf8'));
const pkgs = j.packages ?? [];
const byId = new Map(pkgs.map((p) => [p.id, p]));

function methodLine(p) {
  const ms = p.installMethods ?? [];
  if (!ms.length) return '  install: (none published)';
  return ms.slice(0, 2).map((m) =>
    `  install: ${m.kind} spec=${m.spec} verified=${m.verification ?? '?'} rev=${m.revision ?? '?'} needsBuild=${m.requiresBuildAllowance ?? false}${m.buildPackage ? ' build=' + m.buildPackage : ''}`
  ).join('\n');
}

function detail(cat, names) {
  console.log(`\n########## ${cat} ##########`);
  for (const p of pkgs.filter((x) => x.category === cat && names.includes(x.name))) {
    console.log(`${p.name} (${p.owner})  installs=${p.installCount} 30d=${p.installs30d} 7d=${p.installs7d} fail=${p.failureCount} remove=${p.removeCount} recommit=${p.reinstallCount} npm7d=${p.npmDownloads7d} stars=${p.stars}`);
    console.log(`  url=${p.url}  latestReleaseAt=${(p.latestReleaseAt ?? '').slice(0, 10)}  pushedAt=${(p.pushedAt ?? '').slice(0, 10)}  added=${(p.added ?? '').slice(0, 10)}`);
    console.log(methodLine(p));
    console.log('');
  }
}

detail('memory', ['dsh-memory-plugin', 'coding-agents', 'dsh-mnemon', 'memsearch-dsh', 'dsh-memoir', 'dsh-plugin', 'memos-local-plugin', 'dsh-memory-meow', 'dsh-knowledge']);
detail('theme', ['skin-center', 'dsh-skin-market', 'dsh-wallpaper-engine', 'dsh-opencode-palette', 'dsh-catppuccin-theme', 'dsh-liang-skin', 'open-sea-skin', 'dsh-kimino-theme']);

console.log('\n########## newest (rankings.newest) — categories of interest ##########');
const newest = (j.rankings?.newest ?? []).map((r) => byId.get(r.id ?? r) ?? r).filter(Boolean);
for (const p of newest.slice(0, 25)) {
  if (!p.category) continue;
  console.log(`  [${p.category}] ${p.name} (${p.owner}) added=${(p.added ?? '').slice(0, 10)} installs=${p.installCount} npm7d=${p.npmDownloads7d}  ${String(p.description?.zh ?? p.description ?? '').replace(/\s+/g, ' ').slice(0, 110)}`);
}

console.log('\n########## hottest by installs (all categories) ##########');
const top = (j.rankings?.installs ?? []).map((r) => byId.get(r.id ?? r) ?? r).filter(Boolean);
for (const p of top.slice(0, 12)) {
  console.log(`  [${p.category}] ${p.name} (${p.owner}) installs=${p.installCount} 30d=${p.installs30d} fail=${p.failureCount}  ${String(p.description?.zh ?? p.description ?? '').replace(/\s+/g, ' ').slice(0, 100)}`);
}
