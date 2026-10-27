// Connectivity matrix using Node's bundled OpenSSL (same TLS stack as DSH web_fetch).
import { request } from 'node:https';
import { lookup } from 'node:dns/promises';

const hosts = [
  'example.com',
  'www.baidu.com',
  'www.sdo.com',
  'github.com',
  'raw.githubusercontent.com',
  'api.github.com',
  'registry.npmjs.org',
  'www.google.com',
];

const tlsProbe = (host, path = '/') => new Promise((resolve) => {
  const t = setTimeout(() => { req.destroy(); resolve('TIMEOUT'); }, 12000);
  const req = request(
    { host, port: 443, path, method: 'HEAD', headers: { 'user-agent': 'dsh-netprobe' }, timeout: 12000 },
    (res) => { clearTimeout(t); res.resume(); resolve('HTTP ' + res.statusCode); },
  );
  req.on('error', (e) => { clearTimeout(t); resolve('ERR ' + (e.code || e.message)); });
  req.on('timeout', () => { clearTimeout(t); req.destroy(); resolve('TIMEOUT'); });
  req.end();
});

const dnsProbe = async (host) => {
  try { const a = await lookup(host, { all: true }); return a.map((x) => x.address).slice(0, 3).join(','); }
  catch (e) { return 'DNSFAIL ' + (e.code || e.message); }
};

console.log('host'.padEnd(28), 'dns'.padEnd(40), 'tls');
console.log('-'.repeat(90));
for (const h of hosts) {
  const dns = await dnsProbe(h);
  const tls = await tlsProbe(h);
  console.log(h.padEnd(28), dns.padEnd(40), tls);
}
