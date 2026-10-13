// M0 spike: which redirect URIs and grants does Coros accept for a secret-less public client?
// Registers anonymous public clients and checks /oauth2/authorize; never signs in.
import crypto from 'node:crypto';

const META = 'https://mcp.coros.com/.well-known/oauth-authorization-server';
const MCP_URL = 'https://mcp.coros.com/mcp';
const SCOPE = 'openid offline_access mcp.tools';

const meta = await (await fetch(META)).json();
const b64url = (b) => b.toString('base64url');

async function register(redirectUris, grantTypes) {
  const res = await fetch(meta.registration_endpoint, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      client_name: 'Training Companion spike',
      redirect_uris: redirectUris,
      grant_types: grantTypes,
      response_types: ['code'],
      scope: SCOPE,
      token_endpoint_auth_method: 'none',
    }),
  });
  const body = await res.json().catch(() => ({}));
  return { status: res.status, body };
}

async function authorize(clientId, redirectUri) {
  const verifier = b64url(crypto.randomBytes(32));
  const q = new URLSearchParams({
    response_type: 'code', client_id: clientId, redirect_uri: redirectUri, scope: SCOPE,
    code_challenge: b64url(crypto.createHash('sha256').update(verifier).digest()),
    code_challenge_method: 'S256', resource: MCP_URL, state: b64url(crypto.randomBytes(12)),
  });
  const res = await fetch(`${meta.authorization_endpoint}?${q}`, { redirect: 'manual' });
  const loc = res.headers.get('location') ?? '';
  let text = '';
  if (!loc) text = (await res.text()).slice(0, 200).replace(/\s+/g, ' ');
  return { status: res.status, location: loc.split('?')[0], error: new URL(loc || 'x:/', 'x:/').searchParams.get('error') ?? '', text };
}

const cases = [
  ['custom scheme (path 1)', 'com.trainingcompanion.app:/oauth/callback'],
  ['custom scheme, // form', 'trainingcompanion://oauth/callback'],
  ['https app link (path 1)', 'https://trainingcompanion.example/oauth/callback'],
  ['loopback (path 2)', 'http://127.0.0.1:43123/callback'],
];

for (const [label, uri] of cases) {
  const reg = await register([uri], ['authorization_code', 'refresh_token']);
  const ok = reg.status === 200 || reg.status === 201;
  console.log(`\n## ${label}: ${uri}`);
  console.log(`register -> ${reg.status} ${ok ? 'client_id=' + reg.body.client_id.slice(0, 8) + '...' : JSON.stringify(reg.body)}`);
  if (ok) {
    if (reg.body.redirect_uris) console.log(`  stored redirect_uris: ${JSON.stringify(reg.body.redirect_uris)}`);
    const a = await authorize(reg.body.client_id, uri);
    console.log(`authorize -> ${a.status} location=${a.location} ${a.error ? 'error=' + a.error : ''} ${a.text}`);
  }
}

// Path 4 (new): RFC 8628 device flow, advertised in metadata
console.log('\n## device flow (path 4, not in PRD)');
const dreg = await register([], ['urn:ietf:params:oauth:grant-type:device_code', 'refresh_token']);
console.log(`register -> ${dreg.status} ${dreg.body.client_id ? 'client_id ok, grant_types=' + JSON.stringify(dreg.body.grant_types) : JSON.stringify(dreg.body)}`);
if (dreg.body.client_id) {
  const res = await fetch(meta.device_authorization_endpoint, {
    method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ client_id: dreg.body.client_id, scope: SCOPE, resource: MCP_URL }),
  });
  const body = await res.json().catch(() => ({}));
  console.log(`device_authorization -> ${res.status} ${body.verification_uri ? 'verification_uri=' + body.verification_uri + ' user_code present=' + !!body.user_code + ' interval=' + body.interval : JSON.stringify(body)}`);
}
