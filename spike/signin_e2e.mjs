// M0 spike, run on the laptop: does Coros accept a secret-less, self-registered client end to end?
// Mirrors what the Android app will do: register (no secret) -> PKCE authorize -> loopback redirect
// -> token exchange -> refresh -> MCP calls. Tokens are kept in memory only and never written to disk.
//
//   node signin_e2e.mjs                       read-only: sign in, refresh, read one day of data
//   node signin_e2e.mjs --auth-port 51877     register port 43123 but sign in on another port
//   node signin_e2e.mjs --write-workout       also save one easy Zone 2 run to the Coros workout library
//   node signin_e2e.mjs --inspect             also report outputSchema and the full shape of each reply
import crypto from 'node:crypto';
import http from 'node:http';
import { spawn } from 'node:child_process';

const args = process.argv.slice(2);
const flag = (name) => args.includes(name);
const opt = (name, def) => (args.includes(name) ? args[args.indexOf(name) + 1] : def);

const MCP_URL = 'https://mcp.coros.com/mcp';
const SCOPE = 'openid offline_access mcp.tools';
const REGISTER_PORT = Number(opt('--register-port', 43123));
const AUTH_PORT = Number(opt('--auth-port', REGISTER_PORT));
const registeredRedirect = `http://127.0.0.1:${REGISTER_PORT}/callback`;
const redirectUri = `http://127.0.0.1:${AUTH_PORT}/callback`;
const SIGN_IN_TIMEOUT_MS = 5 * 60 * 1000;

const step = (msg) => console.log(`\n[${new Date().toISOString().slice(11, 19)}] ${msg}`);
const b64url = (buf) => buf.toString('base64url');
const redact = (t) => (t ? `${t.slice(0, 6)}...(${t.length} chars)` : String(t));

async function readBody(res) {
  const raw = await res.text();
  if (!raw) return {};
  if ((res.headers.get('content-type') ?? '').includes('text/event-stream')) {
    const events = raw.split(/\r?\n\r?\n/).map((e) => e.split(/\r?\n/).filter((l) => l.startsWith('data:')).map((l) => l.slice(5).trim()).join('\n')).filter(Boolean);
    return JSON.parse(events.at(-1));
  }
  try { return JSON.parse(raw); } catch { return { raw: raw.slice(0, 300) }; }
}

// 1. Discover the regional issuer from metadata, never hard-code it.
step('Reading OAuth metadata');
const meta = await (await fetch('https://mcp.coros.com/.well-known/oauth-authorization-server')).json();
console.log(`issuer=${meta.issuer}`);

// 2. Register a public client with no secret.
step(`Registering public client, redirect ${registeredRedirect}`);
const regRes = await fetch(meta.registration_endpoint, {
  method: 'POST',
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify({
    // Coros returns the same client_id for a repeated client_name, so make it unique per install.
    client_name: `Training Companion · ${crypto.randomUUID().slice(0, 8)}`,
    redirect_uris: [registeredRedirect],
    grant_types: ['authorization_code', 'refresh_token'],
    response_types: ['code'],
    scope: SCOPE,
    token_endpoint_auth_method: 'none',
  }),
});
const reg = await regRes.json();
if (!reg.client_id) throw new Error(`registration failed ${regRes.status}: ${JSON.stringify(reg)}`);
const clientId = reg.client_id;
console.log(`registered ${regRes.status}, client_id=${redact(clientId)}`);

// 3. PKCE authorize in the user's browser, catch the code on the loopback listener.
const verifier = b64url(crypto.randomBytes(32));
const state = b64url(crypto.randomBytes(24));
const authorizeUrl = `${meta.authorization_endpoint}?${new URLSearchParams({
  response_type: 'code', client_id: clientId, redirect_uri: redirectUri, scope: SCOPE,
  code_challenge: b64url(crypto.createHash('sha256').update(verifier).digest()),
  code_challenge_method: 'S256', resource: MCP_URL, state,
})}`;

const callback = await new Promise((resolve, reject) => {
  const server = http.createServer((req, res) => {
    const url = new URL(req.url, redirectUri);
    if (url.pathname !== '/callback') { res.writeHead(404).end(); return; }
    const params = Object.fromEntries(url.searchParams);
    res.writeHead(200, { 'content-type': 'text/html' })
      .end(`<body style="background:#000;color:#fff;font-family:sans-serif;padding:40px"><h2>${params.code ? 'Signed in. You can close this tab.' : 'Sign-in failed: ' + (params.error ?? 'unknown')}</h2></body>`);
    server.close();
    resolve(params);
  });
  server.on('error', reject);
  server.listen(AUTH_PORT, '127.0.0.1', () => {
    step(`Listening on ${redirectUri}; opening the Coros sign-in page in your browser`);
    console.log(`If no tab opens, visit:\n${authorizeUrl}`);
    spawn('rundll32', ['url.dll,FileProtocolHandler', authorizeUrl], { detached: true, stdio: 'ignore' }).unref();
  });
  setTimeout(() => { server.close(); reject(new Error('timed out waiting for sign-in')); }, SIGN_IN_TIMEOUT_MS).unref();
});

if (callback.error) throw new Error(`authorize returned error=${callback.error} ${callback.error_description ?? ''}`);
if (callback.state !== state) throw new Error('state mismatch');
console.log(`got code=${redact(callback.code)}, state matches`);

// 4. Exchange the code with no secret.
async function tokenRequest(form) {
  const res = await fetch(meta.token_endpoint, {
    method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams(form),
  });
  const body = await res.json();
  if (res.status !== 200) throw new Error(`token ${form.grant_type} failed ${res.status}: ${JSON.stringify(body)}`);
  return body;
}
step('Exchanging code for tokens');
let tokens = await tokenRequest({ grant_type: 'authorization_code', client_id: clientId, code: callback.code, redirect_uri: redirectUri, code_verifier: verifier });
console.log(`access=${redact(tokens.access_token)} refresh=${redact(tokens.refresh_token)} expires_in=${tokens.expires_in}s scope="${tokens.scope}"`);

// 5. Refresh once, with no secret, and use the refreshed token for everything after.
step('Refreshing tokens');
const refreshed = await tokenRequest({ grant_type: 'refresh_token', client_id: clientId, refresh_token: tokens.refresh_token });
console.log(`new access=${redact(refreshed.access_token)} refresh rotated=${!!refreshed.refresh_token && refreshed.refresh_token !== tokens.refresh_token} expires_in=${refreshed.expires_in}s`);
tokens = { ...tokens, ...refreshed };

// 6. MCP over HTTP JSON-RPC.
let rpcId = 0;
async function mcp(method, params = {}) {
  const res = await fetch(MCP_URL, {
    method: 'POST',
    headers: { authorization: `Bearer ${tokens.access_token}`, accept: 'application/json, text/event-stream', 'content-type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: ++rpcId, method, params }),
  });
  const body = await readBody(res);
  if (res.status !== 200 || body.error) throw new Error(`mcp ${method} failed ${res.status}: ${JSON.stringify(body.error ?? body).slice(0, 300)}`);
  return body.result;
}
// --inspect: report the full shape of a tool result, not just its text (is structuredContent there?)
function describeResult(name, result) {
  const shape = {
    resultKeys: Object.keys(result),
    contentTypes: (result.content ?? []).map((c) => c.type + (c.mimeType ? `(${c.mimeType})` : '')),
    structuredContent: result.structuredContent === undefined ? 'absent' : typeof result.structuredContent,
  };
  const text = (result.content ?? []).find((c) => c.type === 'text')?.text ?? '';
  let decoded;
  try { decoded = JSON.parse(text); } catch { decoded = undefined; }
  shape.textIsJson = decoded === undefined ? 'no' : Array.isArray(decoded) ? 'array' : typeof decoded;
  console.log(`  shape of ${name}: ${JSON.stringify(shape)}`);
  if (result.structuredContent !== undefined) {
    console.log(`  structuredContent sample: ${JSON.stringify(result.structuredContent).slice(0, 600)}`);
  }
}

const callTool = async (name, toolArgs) => {
  const result = await mcp('tools/call', { name, arguments: toolArgs });
  if (flag('--inspect')) describeResult(name, result);
  const text = (result.content ?? []).filter((c) => c.type === 'text').map((c) => c.text).join('\n');
  return { isError: !!result.isError, text };
};

step('MCP initialize');
const init = await mcp('initialize', { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'Training Companion', version: '0.0.1' } });
console.log(`server=${init.serverInfo?.name} ${init.serverInfo?.version ?? ''} protocol=${init.protocolVersion}`);

step('MCP tools/list');
const tools = (await mcp('tools/list')).tools ?? [];
console.log(`${tools.length} tools: ${tools.map((t) => t.name).join(', ')}`);
if (flag('--inspect')) {
  const withSchema = tools.filter((t) => t.outputSchema);
  console.log(`tools declaring an outputSchema: ${withSchema.length ? withSchema.map((t) => t.name).join(', ') : 'none'}`);
  const toolKeys = [...new Set(tools.flatMap((t) => Object.keys(t)))];
  console.log(`keys present on tool definitions: ${toolKeys.join(', ')}`);
  for (const t of withSchema.slice(0, 3)) console.log(`  ${t.name} outputSchema: ${JSON.stringify(t.outputSchema).slice(0, 400)}`);
}

const today = new Date();
const ymd = (d) => d.toISOString().slice(0, 10).replaceAll('-', '');
const reads = [
  ['querySleepHrv', { startDate: ymd(today), endDate: ymd(today), days: 1 }],
  ['queryDailyHealthData', { days: 1 }],
  ['queryRestingHeartRate', { days: 1 }],
  ['queryTrainingLoadAssessment', { days: 1 }],
];
if (flag('--inspect')) {
  const weekAgo = new Date(today.getTime() - 7 * 86400000);
  reads.push(['queryUserInfo', {}], ['querySportRecords', { startDate: ymd(weekAgo), endDate: ymd(today), limit: 3 }]);
}
for (const [name, toolArgs] of reads) {
  step(`Reading ${name} ${JSON.stringify(toolArgs)}`);
  const r = await callTool(name, toolArgs);
  console.log(`${r.isError ? 'ERROR ' : ''}${r.text.length} chars:\n${r.text.slice(0, 700)}${r.text.length > 700 ? '\n...' : ''}`);
}

if (flag('--write-workout')) {
  step('Writing one workout to the Coros library (createSingleWorkout)');
  const r = await callTool('createSingleWorkout', {
    course: {
      courseName: 'TC spike: Easy 30 min Zone 2',
      courseDescription: 'Test workout from the Training Companion app. Run easy for 30 minutes and keep your heart rate in Zone 2. Safe to delete.',
      sportType: 1,
      sections: [{ sectionType: 2, targetType: 2, targetValue: 1800, intensityType: 1, sectionIntensity: 2 }],
    },
  });
  console.log(`${r.isError ? 'ERROR ' : ''}${r.text.slice(0, 500)}`);
}

step('Done: sign-in, refresh and MCP reads all succeeded');
