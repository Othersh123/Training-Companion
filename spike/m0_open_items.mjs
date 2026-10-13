// M0 spike, open items, all in one sign-in:
//   1. Port: register redirect port 43123, sign in on port 51877. Does Coros accept the unregistered port?
//   2. Routes: does getActivityDetail return GPS track points for an outdoor run?
//   3. Revocation: can a public client (no secret) revoke its tokens, and does Coros then refuse them?
// If Coros rejects port 51877 (no callback within 3 minutes), it retries once on the registered port
// so tests 2 and 3 still run. Tokens stay in memory only.
import crypto from 'node:crypto';
import http from 'node:http';
import { spawn } from 'node:child_process';

const MCP_URL = 'https://mcp.coros.com/mcp';
const SCOPE = 'openid offline_access mcp.tools';
const REGISTERED_PORT = 43123;
const TEST_PORT = 51877;
const ATTEMPT_TIMEOUT_MS = 3 * 60 * 1000;

const results = {};
const step = (msg) => console.log(`\n[${new Date().toISOString().slice(11, 19)}] ${msg}`);
const b64url = (buf) => buf.toString('base64url');
const redact = (t) => (t ? `${t.slice(0, 6)}...(${t.length} chars)` : String(t));
const callbackUri = (port) => `http://127.0.0.1:${port}/callback`;

const meta = await (await fetch('https://mcp.coros.com/.well-known/oauth-authorization-server')).json();
step(`issuer=${meta.issuer}; revocation auth methods: ${JSON.stringify(meta.revocation_endpoint_auth_methods_supported)}`);

const regRes = await fetch(meta.registration_endpoint, {
  method: 'POST',
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify({
    client_name: `Training Companion · ${crypto.randomUUID().slice(0, 8)}`,
    redirect_uris: [callbackUri(REGISTERED_PORT)],
    grant_types: ['authorization_code', 'refresh_token'],
    response_types: ['code'],
    scope: SCOPE,
    token_endpoint_auth_method: 'none',
  }),
});
const reg = await regRes.json();
if (!reg.client_id) throw new Error(`registration failed ${regRes.status}: ${JSON.stringify(reg)}`);
const clientId = reg.client_id;
step(`registered ${regRes.status} with redirect port ${REGISTERED_PORT} only; client_id=${redact(clientId)}`);

// One browser sign-in on a given port. Resolves with {code, verifier, redirectUri} or {failed: reason}.
function signIn(port) {
  const redirectUri = callbackUri(port);
  const verifier = b64url(crypto.randomBytes(32));
  const state = b64url(crypto.randomBytes(24));
  const url = `${meta.authorization_endpoint}?${new URLSearchParams({
    response_type: 'code', client_id: clientId, redirect_uri: redirectUri, scope: SCOPE,
    code_challenge: b64url(crypto.createHash('sha256').update(verifier).digest()),
    code_challenge_method: 'S256', resource: MCP_URL, state,
  })}`;
  return new Promise((resolve) => {
    const server = http.createServer((req, res) => {
      const u = new URL(req.url, redirectUri);
      if (u.pathname !== '/callback') { res.writeHead(404).end(); return; }
      const p = Object.fromEntries(u.searchParams);
      res.writeHead(200, { 'content-type': 'text/html' })
        .end(`<body style="background:#000;color:#fff;font-family:sans-serif;padding:40px"><h2>${p.code ? 'Signed in. You can close this tab.' : 'Sign-in failed: ' + (p.error ?? 'unknown')}</h2></body>`);
      server.close();
      if (p.error) resolve({ failed: `error=${p.error} ${p.error_description ?? ''}` });
      else if (p.state !== state) resolve({ failed: 'state mismatch' });
      else resolve({ code: p.code, verifier, redirectUri });
    });
    server.listen(port, '127.0.0.1', () => {
      step(`Listening on ${redirectUri}; opening Coros sign-in in the browser`);
      console.log(`If no tab opens, visit:\n${url}`);
      spawn('rundll32', ['url.dll,FileProtocolHandler', url], { detached: true, stdio: 'ignore' }).unref();
    });
    setTimeout(() => { server.close(); resolve({ failed: 'no callback within 3 minutes' }); }, ATTEMPT_TIMEOUT_MS).unref();
  });
}

async function tokenRequest(form) {
  const res = await fetch(meta.token_endpoint, { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams(form) });
  return { status: res.status, body: await res.json().catch(() => ({})) };
}

// ---- Test 1: unregistered port ----
step(`TEST 1: sign in on unregistered port ${TEST_PORT}`);
let signed = await signIn(TEST_PORT);
let tokens;
if (!signed.failed) {
  const t = await tokenRequest({ grant_type: 'authorization_code', client_id: clientId, code: signed.code, redirect_uri: signed.redirectUri, code_verifier: signed.verifier });
  results.port = t.status === 200 ? `PASS: Coros redirected to port ${TEST_PORT} and the token exchange succeeded` : `PARTIAL: callback arrived on ${TEST_PORT} but token exchange failed ${t.status} ${JSON.stringify(t.body)}`;
  if (t.status === 200) tokens = t.body;
} else {
  results.port = `FAIL: ${signed.failed}`;
}
console.log(results.port);

if (!tokens) {
  step(`Retrying on the registered port ${REGISTERED_PORT} so tests 2 and 3 can run`);
  signed = await signIn(REGISTERED_PORT);
  if (signed.failed) throw new Error(`sign-in on the registered port failed too: ${signed.failed}`);
  const t = await tokenRequest({ grant_type: 'authorization_code', client_id: clientId, code: signed.code, redirect_uri: signed.redirectUri, code_verifier: signed.verifier });
  if (t.status !== 200) throw new Error(`token exchange failed ${t.status}: ${JSON.stringify(t.body)}`);
  tokens = t.body;
}
console.log(`access=${redact(tokens.access_token)} refresh=${redact(tokens.refresh_token)}`);

// ---- MCP helpers ----
async function mcpRaw(accessToken, method, params = {}) {
  const res = await fetch(MCP_URL, {
    method: 'POST',
    headers: { authorization: `Bearer ${accessToken}`, accept: 'application/json, text/event-stream', 'content-type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }),
  });
  const raw = await res.text();
  let body = {};
  if ((res.headers.get('content-type') ?? '').includes('text/event-stream')) {
    const data = raw.split(/\r?\n/).filter((l) => l.startsWith('data:')).map((l) => l.slice(5).trim());
    try { body = JSON.parse(data.at(-1)); } catch { body = { raw: raw.slice(0, 200) }; }
  } else {
    try { body = JSON.parse(raw); } catch { body = { raw: raw.slice(0, 200) }; }
  }
  return { status: res.status, body };
}
async function toolText(name, args) {
  const r = await mcpRaw(tokens.access_token, 'tools/call', { name, arguments: args });
  if (r.status !== 200 || r.body.error) throw new Error(`${name} failed ${r.status}: ${JSON.stringify(r.body.error ?? r.body).slice(0, 300)}`);
  let text = (r.body.result.content ?? []).filter((c) => c.type === 'text').map((c) => c.text).join('\n');
  try { const decoded = JSON.parse(text); if (typeof decoded === 'string') text = decoded; } catch { /* already plain */ }
  return text;
}

// ---- Test 2: GPS track in activity detail ----
step('TEST 2: does getActivityDetail carry GPS track points?');
const ymd = (d) => d.toISOString().slice(0, 10).replaceAll('-', '');
const now = new Date();
const records = await toolText('querySportRecords', { startDate: ymd(new Date(now - 30 * 86400000)), endDate: ymd(now), sportTypeCodes: [100, 102], limit: 5 });
const run = records.match(/LabelId: (\d+) \| SportType: (\d+)/);
const hasStart = /Start Coordinates:/.test(records);
if (!run) {
  results.routes = 'INCONCLUSIVE: no outdoor or trail run in the last 30 days';
} else {
  const [, labelId, sportType] = run;
  console.log(`using the most recent outdoor run, sportType ${sportType}`);
  const detail = await toolText('getActivityDetail', { labelId, sportType: Number(sportType) });
  const coordPairs = detail.match(/-?\d{1,3}\.\d{4,}\s*,\s*-?\d{1,3}\.\d{4,}/g) ?? [];
  const keywords = ['lat', 'lon', 'lng', 'gps', 'track', 'coordinate', 'polyline', 'route'].filter((k) => detail.toLowerCase().includes(k));
  // Section titles: short lines that end with a colon or contain an em dash, as the other reports use.
  const headers = [...new Set(detail.split('\n').map((l) => l.trim()).filter((l) => l.length < 60 && (/:$/.test(l) || l.includes('—'))))].slice(0, 25);
  console.log(`detail: ${detail.length} chars, coordinate-like pairs: ${coordPairs.length}, location keywords: ${keywords.join(', ') || 'none'}`);
  console.log(`section lines:\n  ${headers.join('\n  ')}`);
  results.routes = coordPairs.length > 20
    ? `YES: activity detail carries ${coordPairs.length} coordinate pairs; routes may not need FIT files`
    : `NO: activity detail has ${coordPairs.length} coordinate pairs (list has start point: ${hasStart}); routes need FIT files`;
}
console.log(results.routes);

// ---- Test 3: revocation without a secret ----
step('TEST 3: revoke tokens as a public client');
const before = await mcpRaw(tokens.access_token, 'tools/list');
console.log(`before revoking: MCP tools/list -> ${before.status}`);

async function revoke(token, hint) {
  const res = await fetch(meta.revocation_endpoint, {
    method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ token, token_type_hint: hint, client_id: clientId }),
  });
  return `${res.status} ${(await res.text()).slice(0, 200)}`;
}
const revokeAccess = await revoke(tokens.access_token, 'access_token');
console.log(`revoke access_token -> ${revokeAccess}`);
const afterAccess = await mcpRaw(tokens.access_token, 'tools/list');
console.log(`MCP with the revoked access token -> ${afterAccess.status} ${afterAccess.status === 200 ? '(still accepted)' : '(refused)'}`);

const revokeRefresh = await revoke(tokens.refresh_token, 'refresh_token');
console.log(`revoke refresh_token -> ${revokeRefresh}`);
const afterRefresh = await tokenRequest({ grant_type: 'refresh_token', client_id: clientId, refresh_token: tokens.refresh_token });
console.log(`refresh with the revoked refresh token -> ${afterRefresh.status} ${afterRefresh.status === 200 ? "(new tokens issued, not printed)" : JSON.stringify(afterRefresh.body).slice(0, 150)}`);

results.revocation = `access token ${afterAccess.status === 200 ? 'STILL WORKS after revoke' : 'refused after revoke'}; refresh token ${afterRefresh.status === 200 ? 'STILL WORKS after revoke' : 'refused after revoke'}`;

step('SUMMARY');
for (const [k, v] of Object.entries(results)) console.log(`${k.padEnd(10)} ${v}`);
