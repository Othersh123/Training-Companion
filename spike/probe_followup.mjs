import crypto from 'node:crypto';
const meta = await (await fetch('https://mcp.coros.com/.well-known/oauth-authorization-server')).json();
const MCP_URL = 'https://mcp.coros.com/mcp', SCOPE = 'openid offline_access mcp.tools';
const reg = async (uris, grants) => { const r = await fetch(meta.registration_endpoint, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ client_name: 'Training Companion spike', redirect_uris: uris, grant_types: grants, response_types: ['code'], scope: SCOPE, token_endpoint_auth_method: 'none' }) }); return { status: r.status, body: await r.json().catch(() => ({})) }; };
const authz = async (cid, uri) => { const q = new URLSearchParams({ response_type: 'code', client_id: cid, redirect_uri: uri, scope: SCOPE, code_challenge: crypto.randomBytes(32).toString('base64url'), code_challenge_method: 'S256', resource: MCP_URL, state: 'x' }); const r = await fetch(`${meta.authorization_endpoint}?${q}`, { redirect: 'manual' }); const loc = r.headers.get('location') ?? ''; return `${r.status} ${loc.split('?')[0]} ${new URL(loc || 'x:/').searchParams.get('error') ?? ''} ${loc ? '' : (await r.text()).slice(0, 150).replace(/\s+/g, ' ')}`; };

console.log('## loopback port variation');
const lb = await reg(['http://127.0.0.1:43123/callback'], ['authorization_code', 'refresh_token']);
for (const u of ['http://127.0.0.1:43123/callback', 'http://127.0.0.1:51877/callback', 'http://127.0.0.1/callback', 'http://localhost:43123/callback'])
  console.log(`  ${u} -> ${await authz(lb.body.client_id, u)}`);
console.log('## register loopback without port, then use a random port');
const np = await reg(['http://127.0.0.1/callback'], ['authorization_code', 'refresh_token']);
console.log(`  register -> ${np.status} ${np.body.error_description ?? ''}`);
if (np.body.client_id) console.log(`  :51877 -> ${await authz(np.body.client_id, 'http://127.0.0.1:51877/callback')}`);

console.log('## device flow with a placeholder redirect');
for (const grants of [['urn:ietf:params:oauth:grant-type:device_code', 'refresh_token'], ['authorization_code', 'urn:ietf:params:oauth:grant-type:device_code', 'refresh_token']]) {
  const d = await reg(['http://127.0.0.1:43123/callback'], grants);
  console.log(`  register ${JSON.stringify(grants)} -> ${d.status} ${d.body.client_id ? 'stored grants=' + JSON.stringify(d.body.grant_types) : JSON.stringify(d.body)}`);
  if (!d.body.client_id) continue;
  const r = await fetch(meta.device_authorization_endpoint, { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ client_id: d.body.client_id, scope: SCOPE, resource: MCP_URL }) });
  const b = await r.json().catch(() => ({}));
  console.log(`  device_authorization -> ${r.status} ${b.device_code ? `verification_uri=${b.verification_uri} complete=${!!b.verification_uri_complete} expires_in=${b.expires_in} interval=${b.interval}` : JSON.stringify(b)}`);
}
