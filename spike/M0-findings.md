# M0 spike findings

Run from the laptop on 2 Oct 2026. Scripts are in this folder.

## Environment

Flutter SDK, Android Studio / Android SDK, a JDK and adb are not installed on this laptop, so the Android half of M0 (an on-phone sign-in, the home screen widget) cannot be built or run yet. The Coros server behaviour, which is the main M0 risk, was tested from Node instead, using exactly the requests the app will make.

## Coros OAuth server (probe_redirects.mjs, probe_followup.mjs, probe_validate.mjs)

| Check | Result |
| --- | --- |
| Metadata | Issuer `https://mcpus.coros.com`. `token_endpoint_auth_methods_supported` now lists `none`, so secret-less clients are officially supported (the PRD said they weren't listed). |
| Self-registration, no secret | Works (201) for https and loopback redirect URIs. |
| Custom scheme redirect, e.g. `com.trainingcompanion.app:/oauth/callback` | **Rejected at registration**: "Remote redirect_uri must use https". |
| https redirect (App Link) | Accepted at registration. Needs a domain we control hosting `/.well-known/assetlinks.json`. |
| Loopback `http://127.0.0.1:<port>/callback` | Accepted at registration. |
| Device flow (RFC 8628) | Advertised in metadata, but registration silently strips the `device_code` grant and `/oauth2/device_authorization` returns 401. **Not available to self-registered apps.** |
| Revocation | `revocation_endpoint_auth_methods_supported` does not include `none`, so a public client may not be able to revoke tokens on disconnect. To test. |
| Where redirect_uri is validated | Not at the first `/authorize` hop. Coros brokers to its own login (`openus.coros.com`) with its own callback, and checks our redirect only after sign-in. Port flexibility can only be proven with a real sign-in. |

## What this means for the three sign-in paths

1. **Custom scheme:** dead, Coros requires https for non-loopback redirects.
2. **Loopback:** the only path that works with no domain and no undocumented APIs. Android risk remains: the app's listener must stay alive while the Custom Tab is in front (a foreground service or a short-lived listener usually works).
3. **https App Link:** works on the Coros side but needs a domain serving a static `assetlinks.json` file (not a relay; no tokens pass through it). Fallback if loopback fails on Android.
4. **Login-ticket flow:** still available as a last resort; undocumented.

## End-to-end sign-in with loopback (signin_e2e.mjs), owner's account, 2 Oct 2026

**Passed.** Register (no secret) -> PKCE authorize in the browser -> code caught on `127.0.0.1:43123` -> token exchange -> refresh -> MCP `initialize`, `tools/list` and four reads.

| Step | Result |
| --- | --- |
| Token exchange, no secret | 200. Scope `mcp.tools openid offline_access`. |
| Access token lifetime | 30 days (`expires_in` 2,591,999 s). |
| Refresh, no secret | 200. **The refresh token rotates on every refresh**, so the app must save the new one atomically each time or it gets locked out. |
| MCP server | `mcp-server 1.0.0`, protocol `2025-06-18`, stateless (no session header needed), 34 tools. |
| querySleepHrv, today | Returned "No data" (the watch hadn't produced last night's HRV yet). |
| queryDailyHealthData, 1 day | Data returned: steps, calories, stress, sleep stages, plus resting HR 58 and HRV baseline 42 in the header. |
| queryRestingHeartRate, 1 day | "No data", although the daily health header carried a resting HR. |
| queryTrainingLoadAssessment, 1 day | Optimized, short 97, long 73, ratio 1.32. |

**Tool results are formatted text, not JSON.** Each result is a human-readable report, for example `Load Ratio: 1.32`. The app needs a parser per tool, with tests on saved responses, and must treat a format change as a sync error rather than silently reading wrong numbers. This is the largest new risk for M1.

Other notes for M1:
- Dates are in the user's Coros timezone, and sleep and HRV are dated by wake-up day. The app should query by the Coros date, not the phone's UTC date.
- The no-data paths are real: on the morning of the test, HRV and resting HR were both missing.

## Workout write (signin_e2e.mjs --write-workout), 2 Oct 2026

**Passed.** `createSingleWorkout` saved "TC spike: Easy 30 min Zone 2" (running, 30 min, heart rate Zone 2) to the owner's Coros library, unscheduled, and returned a Workout ID. The owner can delete it from the Coros app.

The reply is again text written for an AI assistant, with instructions mixed in (for example "Do not call createSingleWorkout again for this same workout"). The app has to pull the Workout ID out with a pattern and ignore the rest.

## Client IDs are shared, not per install

Registering twice with the same `client_name` returns the **same client ID**, even with a different loopback port. A different name gets a new ID. So every install named "Training Companion" would share one Coros client, which contradicts the PRD's "each install gets its own client ID". Recommendation: register with a per-install name, for example "Training Companion · <random install id>", so each phone gets its own client and one friend's setup can't affect another's.

## Still open in M0

- Loopback on a different port than the one registered: untested (needs another sign-in).
- Token revocation for a public client: untested.
- Everything on Android: sign-in from the phone with the listener alive behind a Custom Tab, and the home screen widget. Blocked on Flutter and Android tooling.
