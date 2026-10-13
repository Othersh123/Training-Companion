// Is redirect_uri actually validated at /authorize, or only later? Compare a registered vs an unregistered https URI.
const meta = await (await fetch('https://mcp.coros.com/.well-known/oauth-authorization-server')).json();
const SCOPE = 'openid offline_access mcp.tools';
const r = await fetch(meta.registration_endpoint, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ client_name: 'Training Companion spike', redirect_uris: ['http://127.0.0.1:43123/callback'], grant_types: ['authorization_code', 'refresh_token'], response_types: ['code'], scope: SCOPE, token_endpoint_auth_method: 'none' }) });
const cid = (await r.json()).client_id;
for (const uri of ['http://127.0.0.1:43123/callback', 'https://evil.example/cb', 'http://127.0.0.1:51877/callback']) {
  const q = new URLSearchParams({ response_type: 'code', client_id: cid, redirect_uri: uri, scope: SCOPE, code_challenge: 'a'.repeat(43), code_challenge_method: 'S256', resource: 'https://mcp.coros.com/mcp', state: 'x' });
  const res = await fetch(`${meta.authorization_endpoint}?${q}`, { redirect: 'manual' });
  const loc = new URL(res.headers.get('location'));
  const p = Object.fromEntries(loc.searchParams);
  console.log(`${uri}\n  -> ${res.status} ${loc.origin}${loc.pathname}\n     params: ${JSON.stringify({ ...p, state: p.state ? '[..]' : undefined })}`);
  // follow one hop to the Coros login page, without submitting anything
  const page = await fetch(loc, { redirect: 'manual' });
  console.log(`     login page -> ${page.status} ${page.headers.get('location')?.split('?')[0] ?? ''} ${(await page.text()).match(/<title>[^<]*/)?.[0] ?? ''}`);
}
