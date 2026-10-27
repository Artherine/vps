#!/usr/bin/env node
/**
 * httpsget.mjs — HTTPS fetcher for the DSH Windows sandbox.
 *
 * WHY THIS EXISTS
 * ---------------
 * DSH's Windows shell sandbox runs pwsh under a restricted token at Low
 * integrity. Schannel (the native Windows TLS stack) cannot acquire
 * credentials at that integrity level, so every Schannel-based client fails
 * inside the sandbox with:
 *
 *     curl: (35) schannel: AcquireCredentialsHandle failed:
 *                SEC_E_NO_CREDENTIALS (0x8009030E)
 *     Invoke-WebRequest: The SSL connection could not be established
 *                        -> 安全包中没有可用的凭证
 *
 * Node ships its own OpenSSL and its own CA bundle, so it is unaffected.
 * This script is therefore the working HTTPS path inside the sandbox.
 *
 * The same command run OUTSIDE the sandbox (medium integrity) works fine,
 * and so does DSH's own `web_fetch` tool. The machine's HTTPS is healthy;
 * only Schannel-inside-the-sandbox is broken.
 *
 * Upstream reports: deepseek-harness discussions #997, #1789, #4163.
 *
 * USAGE
 *   node tools/httpsget.mjs <url> [options]
 *
 * OPTIONS
 *   -o, --out <file>     write body to <file> (binary-safe), print only stats
 *   -H, --header <k: v>  add a request header (repeatable)
 *   -X, --method <verb>  HTTP method (default GET)
 *   -d, --data <body>    request body (implies POST unless -X given)
 *       --head           print response headers, no body
 *       --timeout <ms>   total timeout, default 30000
 *       --max <n>        max body bytes to print, default 200000
 *       --json           pretty-print a JSON response body
 *       --insecure       do not verify the TLS certificate
 *   -q, --quiet          suppress the stats banner
 *
 * EXIT CODES
 *   0 success (any HTTP status) | 1 request failed | 2 bad usage
 */

import fs from 'node:fs';
import process from 'node:process';

const USAGE = `usage: node tools/httpsget.mjs <url> [-o file] [-H "K: V"] [-X VERB] [-d BODY]
                                   [--head] [--timeout ms] [--max n] [--json] [--insecure] [-q]`;

function die(msg, code = 2) {
  process.stderr.write(`httpsget: ${msg}\n${USAGE}\n`);
  process.exit(code);
}

const argv = process.argv.slice(2);
if (argv.length === 0 || argv.includes('--help') || argv.includes('-h')) die('no URL given');

const opt = {
  url: null, out: null, headers: {}, method: null, data: null,
  head: false, timeout: 30000, max: 200000, json: false, insecure: false, quiet: false,
};

for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  const next = () => { if (i + 1 >= argv.length) die(`option ${a} needs a value`); return argv[++i]; };
  switch (a) {
    case '-o': case '--out': opt.out = next(); break;
    case '-H': case '--header': {
      const raw = next();
      const k = raw.indexOf(':');
      if (k < 1) die(`bad header (expected "Name: value"): ${raw}`);
      opt.headers[raw.slice(0, k).trim()] = raw.slice(k + 1).trim();
      break;
    }
    case '-X': case '--method': opt.method = next().toUpperCase(); break;
    case '-d': case '--data': opt.data = next(); break;
    case '--head': opt.head = true; break;
    case '--timeout': opt.timeout = Number(next()); break;
    case '--max': opt.max = Number(next()); break;
    case '--json': opt.json = true; break;
    case '--insecure': opt.insecure = true; break;
    case '-q': case '--quiet': opt.quiet = true; break;
    default:
      if (a.startsWith('-')) die(`unknown option ${a}`);
      if (opt.url) die(`unexpected extra argument ${a}`);
      opt.url = a;
  }
}

if (!opt.url) die('no URL given');
if (!/^https?:\/\//i.test(opt.url)) opt.url = 'https://' + opt.url;
if (!Number.isFinite(opt.timeout) || opt.timeout <= 0) die('bad --timeout');

const method = opt.method ?? (opt.data != null ? 'POST' : 'GET');

if (opt.insecure) process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';

let res;
try {
  res = await fetch(opt.url, {
    method,
    headers: {
      'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) dsh-httpsget',
      'accept': '*/*',
      ...(opt.data != null ? { 'content-type': 'application/x-www-form-urlencoded' } : {}),
      ...opt.headers,
    },
    body: opt.data ?? undefined,
    redirect: 'follow',
    signal: AbortSignal.timeout(opt.timeout),
  });
} catch (e) {
  const cause = e?.cause?.code ? ` (${e.cause.code})` : '';
  process.stderr.write(`httpsget: request failed: ${e.name}: ${e.message}${cause}\n`);
  process.exit(1);
}

const buf = Buffer.from(await res.arrayBuffer());
const ctype = res.headers.get('content-type') ?? '';

if (!opt.quiet) {
  process.stderr.write(`HTTP ${res.status} ${res.statusText}\n`);
  process.stderr.write(`url:    ${res.url}\n`);
  if (ctype) process.stderr.write(`type:   ${ctype}\n`);
  process.stderr.write(`bytes:  ${buf.length}\n`);
}

if (opt.head) {
  for (const [k, v] of res.headers) process.stdout.write(`${k}: ${v}\n`);
  process.exit(0);
}

if (opt.out) {
  fs.writeFileSync(opt.out, buf);
  if (!opt.quiet) process.stderr.write(`saved:  ${opt.out}\n`);
  process.exit(0);
}

let text = buf.toString('utf8');
if (opt.json && ctype.includes('json')) {
  try { text = JSON.stringify(JSON.parse(text), null, 2); } catch { /* leave as-is */ }
}

if (text.length > opt.max) {
  process.stdout.write(text.slice(0, opt.max));
  process.stderr.write(`\n[httpsget: truncated at ${opt.max} of ${text.length} chars]\n`);
} else {
  process.stdout.write(text);
  if (text.length && !text.endsWith('\n')) process.stdout.write('\n');
}
