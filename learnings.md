# Learnings

What building Training Companion has taught us so far, and what has to change because of it. Raw test output and scripts are in [spike/](spike/M0-findings.md).

Last updated 5 Oct 2026, during M3.

## Summary

| # | Learning | Impact | Status |
| --- | --- | --- | --- |
| L1 | Sign-in with no client secret works end to end, via a loopback redirect | M0 gate met on the laptop | Confirmed |
| L2 | Custom-scheme redirects are rejected; only loopback or https work | Removes one sign-in path | Confirmed |
| L3 | Coros's device-login flow is closed to self-registered apps | No extra fallback | Confirmed |
| L4 | Refresh tokens rotate on every refresh | Token storage must be atomic | Confirmed |
| L5 | Coros replies are prose written for AI assistants, not JSON | Every tool needs a strict parser; biggest M1 risk | Confirmed |
| L6 | Replies contain instructions aimed at AI assistants | None for the app; matters only if output ever goes to an AI | Confirmed |
| L7 | Coros reuses the client ID for a repeated app name | Installs would share one client; register with a unique name | Confirmed |
| L8 | No-data days are common, even for single signals | No-data paths and parse errors must be kept apart | Confirmed |
| L9 | Dates follow the Coros timezone and the wake-up day | Sync must query by Coros date | Confirmed |
| L10 | Secret-less clients are now listed in Coros metadata | PRD correction | Confirmed |
| L11 | Writing a workout to the library works | M0 write check met | Confirmed |
| L12 | A public client can't revoke its tokens | Disconnect can only delete tokens on the phone | Confirmed |
| L13 | Coros sends no machine-readable data: no `structuredContent`, no `outputSchema` | L5's parsing risk stands | Confirmed |
| L14 | Loopback sign-in works on any port, not just the registered one | Port clashes can't block sign-in | Confirmed |
| L15 | The resting HR in the daily health header changes during the day | Resting HR signal needs a fixed source and read time | Confirmed |
| L16 | Activity records include GPS start coordinates | Home location would land in the database and backup | Confirmed |
| L17 | Activity records carry stable IDs, Unix timestamps and numeric sport codes | Activities are the easiest data to parse reliably | Confirmed |
| L18 | Activity detail has no GPS track | Run map routes must come from FIT files (50 a day) | Confirmed |
| L19 | Sign-in from the Android phone works, with the loopback listener alive in the background | Path 1 is the sign-in route; no App Link domain needed | Confirmed |
| L20 | Android 15+ blocks network for apps in the background | Sign-in finishes the token swap only once the app is back in front; background sync must run as scheduled jobs | Confirmed |
| L21 | Returning from the sign-in page created a second copy of the screen | Fixed with singleTask and a state recheck on resume; root cause still open | Partly understood |
| L22 | The laptop can't reach GitHub's download host from Java, and the first Android build is slow | Setup notes for the build machine | Confirmed |
| L23 | Daily sleep includes naps; only querySleepOverview separates the night | Sleep signal = Main Sleep (asleep) from querySleepOverview | Confirmed |
| L24 | Coros HRV replies carry their own range and rating; a missing night is either "No data" or absent | HRV parser handles both forms | Confirmed |
| L25 | Older Coros history uses formats the recent days don't | Strict parsers caught them on import; now handled and tested | Confirmed |
| L26 | The background job shares the app's database connection | Closing it broke the open app; the job now opens its own | Confirmed |
| L27 | Training load history stops at about 31 days | The 12-week load view starts with a month and fills in from here | Confirmed |
| L28 | Plan workouts appear on the schedule under codes (S5724); the real name and sport are only in the plan details | Fixed 3 Oct 2026: sync reads the plan details; Today shows real names, sport icons and sport-specific advice | Fixed |
| L29 | queryActivityLapData returns real JSON: 1-km splits, and strength sets with the body part | Fitness and body parts parse reliably; one call per activity, fetched once | Confirmed |
| L30 | A week still in progress needs different rules from a finished one | Advice and volume comparisons wait for the week to end; the Sunday summary counts as the end | Fixed |
| L31 | Overflows depend on the phone's text size, and tests measure text in a placeholder font | Charts size bars from leftover space; tests load Inter Tight and check 100% and 130% text on a 360dp screen | Fixed |
| L32 | Coros can't change a plan built in the Coros app, or move or remove workouts; only MCP-created plans are editable | M3 follows and guards the owner's plan; the planner moves after Malnad | Confirmed |
| L33 | Plan workouts carry their full structure; names can be wrong ("7k Easy" set to 10 km) | Workouts are classified and measured from structure, never names | Confirmed |
| L34 | sqflite reuses an open in-memory database; Flutter flags hidden tap ripples | Each screen test gets its own database; tiles draw their own surface | Fixed |
| L35 | Coros says "nothing here" in more wordings than "No data" | Rest-day schedule and no-night HRV replies now read as empty | Fixed |
| L36 | Week-on-week rules misfire right after a recovery week | Volume and long-run growth compare to the biggest of the last 3 weeks; empty pre-race weeks are flagged | Fixed |
| L37 | IFCT 2017 is raw ingredients, and its package changed licence | Recipe builder for dishes; bundle the MIT version; alias list for toor | Fixed |
| L38 | queryDailyHealthData "Calories" is active energy and takes only a day count | Used for food targets; backfill 35 days once | Fixed |
| L39 | Open Food Facts' classic search was down; the newer search service works | Search via search.openfoodfacts.org | Fixed |
| L40 | PRD macro rules left no room for a weight-goal deficit on easy days | Calories win on deficit days; carbs floor 3 g/kg (owner) | Fixed |
| L41 | Python string edits mangled Dart again (newlines, apostrophes) | Use the Edit tool for any Dart string content | Process |
| L42 | Manual entries were guesses: macros didn't match calories | USDA FNDDS estimates with household portions, per item; a check when macros and calories disagree | Fixed |
| L43 | IFCT gives 0 kcal for all oils and ghee | Energy recomputed from macros for 16 foods; stored foods and recipes corrected on app start | Fixed |
| L44 | Snackbars with an action no longer auto-dismiss in this Flutter | persist: false and a 4-second duration on Undo | Fixed |
| L45 | Saved meals refused typed-in entries | Typed-in entries are saved as hidden foods | Fixed |
| L46 | Check now during the background check: "database is locked" | Writes wait up to 10 s; one Coros check at a time through a shared lease | Fixed |
| L47 | Fibre had no target | 14 g per 1,000 kcal (US Institute of Medicine adequate intake); fourth tile on the Log card | Fixed |
| L48 | FIT files carry the full GPS track, and their links need no login | Routes from FIT; links fetched to the phone only | Confirmed |
| L49 | The owner's Coros history starts in 2025; an empty range is a one-line reply | Import from the first year found; "No sport records found" read as empty | Fixed |
| L50 | CARTO map tiles now need a key: every tile is an "API key required" watermark | Free key pasted in Settings; darkened OpenStreetMap tiles until then | Fixed |
| L51 | Owner decision: the owner is the only user, with no friends, store listing or commercial use | Stages 2 and 3, store declarations, crash reporter and public-terms checks dropped from the PRD | Decided |
| L52 | The verdict-only first screen added little over Coros | Home: goal status first, this week, insights; verdict folded to one line | Built |
| L53 | Coros's 50 FIT files a day is a rolling 24 hours, not a calendar day | Budget counted over the last 24 hours; after a limit error, pause until the window frees | Fixed |
| L54 | Coros calls had no timeout: a dropped connection could hang forever | 30 s on MCP calls, 20 s on sign-in requests; screens fail visibly after 20 s and log why | Fixed |
| L55 | The real cause of the endless loading: two database connections on sqflite's single native thread | One shared connection for the app and the background job; no busy wait; background failures logged | Fixed |
| L56 | Preparing a public repo: real-data fixtures carried the owner's home, a usable download ID and a birth date | Coordinates moved 0.5 degrees, FIT file rebuilt, IDs blanked, client ID moved to a git-ignored file | Done |

## Learnings in detail

### L1. Sign-in with no client secret works end to end

Tested with the owner's account on 2 Oct 2026, from the laptop, using the requests the Android app will make: register a public client with no secret, PKCE sign-in in the browser, code caught on `http://127.0.0.1:43123/callback`, token exchange, refresh, then MCP `initialize`, `tools/list` and four data reads. Every step returned 200.

- Access tokens last 30 days.
- The MCP server is stateless JSON-RPC over HTTP with a Bearer token. No session header is needed. Responses can arrive as a server-sent event stream and must be unwrapped.
- 34 tools are available, including every tool the PRD's data table relies on.

**Not yet proven:** the same flow from an Android phone, where the app's loopback listener has to stay alive while a Chrome Custom Tab is in front. That needs Flutter and Android tooling.

### L2. Custom-scheme redirects are rejected

Coros refused to register `com.trainingcompanion.app:/oauth/callback` ("Invalid redirect_uri") and `trainingcompanion://oauth/callback` ("Remote redirect_uri must use https"). Both https and loopback redirects were accepted.

So the PRD's Path 1 works only as an https App Link, which needs a domain we control serving a static `/.well-known/assetlinks.json`. That is a static file, not a relay: no tokens or codes pass through it. Loopback (Path 2) becomes the main path.

### L3. The device-login flow is closed to self-registered apps

Coros's metadata advertises a device authorization endpoint (RFC 8628, the "enter this code on another screen" flow). In practice, registration strips the `device_code` grant from the client, and the endpoint returns 401. It is not an option for us.

### L4. Refresh tokens rotate

Every refresh returns a new refresh token and invalidates the old one. If the app refreshes but fails to save the new token (crash, app killed mid-write, two background jobs refreshing at once), the stored token is dead and the user has to sign in again.

### L5. Coros replies are prose, not JSON

The MCP was built for AI assistants, so each tool returns a human-readable report, for example:

```
Training Load Assessment
2026-10-02
Comment: Optimized
Short-Term Load: 97
Long-Term Load: 73
Load Ratio: 1.32
```

The app has to parse numbers out of this text. Risks:

1. **Coros can change the wording without notice.** An AI wouldn't notice a renamed label or reordered lines; a parser breaks.
2. **A silent misread is the worst outcome.** If a parser can't find a value and treats that as "no data", the morning verdict quietly drops that signal and decides from the rest. On a day with Excessive load, a correct "Go easy" becomes a wrong "Go as planned", with nothing on screen to show it.
3. **Formatting details multiply across about 10 tools:** thousands separators (`1,726`), durations (`1h 0min`), two date styles (`2026-10-02`, `20261002`), "No data" lines, and wording that may follow the Coros account's language.

### L6. Replies contain instructions aimed at AI assistants

The `createSingleWorkout` reply included lines such as "Do not call createSingleWorkout again for this same workout" and "Do not show Workout ID to the user". The app isn't an AI and doesn't act on text, so these are harmless: it takes the Workout ID and ignores the rest. The ID is needed to schedule or edit the workout later, so it is stored but never shown on screen.

This would matter only if Coros output were ever passed to an AI, which is a v1 non-goal.

### L7. Coros reuses the client ID for a repeated app name

Registering twice with the same `client_name` returned the same client ID, even with a different loopback port. A different name got a new ID. Coros appears to look clients up by name, across all of Coros rather than per developer.

The PRD's "Each install gets its own client ID" is therefore wrong. What sharing does and doesn't affect:

- **Data is not shared.** Tokens are issued per person, so each user's tokens open only their own account.
- **The redirect list is shared.** We don't know whether a re-registration with a new address adds it, replaces the old one, or ignores it. If it replaces, one install could break sign-in for every other.
- **Anyone using the same name joins the same client.** A stranger registering "Training Companion" could change its redirect list. PKCE stops them stealing data, but they could cause sign-in failures that are hard to diagnose.
- **Any block or rate limit on the client hits every install at once.** Whether Coros has per-client limits is unknown. The 50 FIT files a day limit is per account and unaffected.

### L8. No-data days are common

On the test morning, querySleepHrv and queryRestingHeartRate both returned "No data" for today, while queryDailyHealthData did return a resting HR (58) in its header. Sleep showed only 55 minutes. Missing signals are an everyday case, not an edge case, and different tools can disagree about whether a value exists.

### L9. Dates follow the Coros timezone and the wake-up day

Coros computes dates in the user's Coros timezone, and dates sleep and HRV by the morning the sleep ended. "Last night" is today's date. The spike script used the laptop's UTC date, which only worked because UTC and India time were on the same date at the time.

### L10. Secret-less clients are now listed in Coros metadata

`token_endpoint_auth_methods_supported` includes `none`. The PRD says the metadata doesn't list secret-less clients; that is out of date.

### L11. Writing a workout works

`createSingleWorkout` saved "TC spike: Easy 30 min Zone 2" (running, 30 minutes, heart-rate Zone 2, unscheduled) to the owner's Coros library and returned a Workout ID. Zone targeting by name works, which confirms the PRD's approach of targeting Zone 2 and letting the watch apply the user's own zones. The owner can delete the test workout from the Coros app.

### L12. A public client can't revoke its tokens

Tested on 2 Oct 2026 with `m0_open_items.mjs`. Revoking the access token and then the refresh token, with `client_id` and no secret, both returned 401. Afterwards the access token still opened the MCP (200) and the refresh token still issued new tokens (200). This matches the metadata, which doesn't list `none` for revocation.

Consequences:

- The app can't cut off its own access. Disconnect and "delete everything" can only delete the tokens on the phone.
- A token copied off the phone stays valid: the access token for up to 30 days, the refresh token until Coros expires it. Keeping tokens in Android Keystore, and out of the Drive backup and the CSV export, becomes essential rather than good practice.
- The only full cut-off is on the Coros side. Whether the Coros app lets a user see and remove authorised apps is unconfirmed.
- Tokens from the spike runs were held only in memory and discarded when each script ended, so none are stored anywhere.

### L13. Coros sends no machine-readable data

Checked on 2 Oct 2026 with `signin_e2e.mjs --inspect` across six tools (querySleepHrv, queryDailyHealthData, queryRestingHeartRate, queryTrainingLoadAssessment, queryUserInfo, querySportRecords):

- No tool in `tools/list` declares an `outputSchema`. Tool definitions carry only `name`, `title`, `description`, `inputSchema` and `annotations`.
- Every reply is `{content: [one text item], isError}`. `structuredContent` is absent.
- The text item is itself a JSON-encoded string: decoding it gives back the same prose report, not data. The app has to decode it once, then parse the prose.

So L5's risk stands in full, and the parser design in "App design changes" is required, not optional.

### L14. Loopback sign-in works on any port

Tested on 2 Oct 2026 with `m0_open_items.mjs`: a client registered with port 43123 signed in on port 51877, Coros redirected there, and the token exchange succeeded. Coros follows the OAuth guidance for native apps that loopback redirects may use any port. The phone app can ask Android for any free port at sign-in time, so a port clash can't block sign-in.

### L15. The daily health resting HR changes during the day

queryDailyHealthData's header showed resting HR 58 bpm at about 14:38 and 49 bpm at about 16:32 India time on the same day, while queryRestingHeartRate returned "No data" for today both times. The header value looks like a rolling figure that updates through the day, not a fixed overnight resting HR. Comparing it against a 30-day average would give different flags depending on when the app reads it.

### L16. Activity records include GPS start coordinates

querySportRecords returns a start latitude and longitude for outdoor activities, to six decimal places. For runs on the home loop, that is effectively the user's home address. If stored as-is, it sits in SQLite, in the Drive backup and in any CSV export. No feature in the PRD needs exact coordinates.

### L17. Activity records are the easiest data to parse

Each record carries a numeric `LabelId` (a stable activity ID), Unix `startTimestamp` and `endTimestamp`, and a numeric `SportType` code (for example 100 outdoor run, 300 pool swim). Duration (`37:12`), distance (`5.02 km` or `725 m`), pace (`7:25 /km`) and average HR also appear in fixed formats. These give the parser firm anchors, and make it possible to de-duplicate activities across syncs.

### L18. Activity detail has no GPS track

getActivityDetail for the most recent outdoor run returned a 479-character summary with no coordinates. The activity list gives only the start point. Full routes for the run map (F5) must come from FIT files, capped at 50 a day per account. That FIT files from Coros carry the GPS track, and that the download tools work, is still untested; it needs checking before M5.

### L19. Sign-in from the Android phone works

Tested on the owner's Samsung SM-S926B (Android 16) on 2 Oct 2026 with the M0 spike app in `app/`. The app listens on a free loopback port, opens Coros sign-in in a Chrome Custom Tab, and catches the code on `127.0.0.1` **while the app is in the background** behind the Custom Tab. Tokens are saved to Keystore-backed storage, and the app then reads data, writes a workout and updates the home screen widget. The PRD's biggest risk is retired: no App Link domain is needed.

### L20. Android blocks network for background apps

The first on-phone sign-in caught the code but failed the token swap with "Failed host lookup: mcpus.coros.com". Android reported the app's network as `blocked=APP_BACKGROUND`: since Android 15, an app that isn't in front, and isn't running a scheduled job or foreground service, has no network. The listener still works, because loopback traffic stays on the phone.

Fix in the spike: hold the code until the app is back in front, then swap it. The callback page sends the user back to the app automatically, with a button as fallback.

For M1 this matters more than sign-in: **the morning sync must run as WorkManager jobs with a network constraint** (which Android lets through), never as plain background code. The widget's Check now must start such a job, or open the app.

### L21. A second copy of the screen appeared after sign-in

In the first on-phone runs, returning from the sign-in page created a new copy of the app's screen. That copy started before the tokens were saved, so it showed "Not connected" and the owner signed in a second time, although the first had worked. After switching the activity to `singleTask` and rechecking sign-in on every resume, sign-in works first time. The log still shows the read after sign-in coming from a different screen instance than the sign-in itself, though only one screen responds to later lifecycle events and Android shows one activity. Root cause to pin down at the start of M1, before background sync and the widget depend on it.

### L22. Build machine notes

- Java can't reach `release-assets.githubusercontent.com` from this laptop's network (connect timeout), while curl can. Gradle's own download of itself failed; it was fetched with curl into `D:\dev\.gradle\wrapper\dists`, checked against Gradle's published SHA-256, and used from there. Any future Gradle version bump needs the same workaround.
- The first Android build needs NDK 28.2 and CMake (about 2.5 GB) because `url_launcher_android` now uses the `jni` package, which compiles native code. The old `sdkmanager` mangles package names; the new `android sdk install ndk/<version>` works.
- The first build took about 45 minutes, mostly downloads and native compiles for three processor types. Building only for the phone (`--target-platform android-arm64`) and with caches warm, rebuilds take about a minute.
- Debug APKs are about 86 MB; release builds will be far smaller.

### L23. Daily sleep includes naps

On 2 Oct, queryDailyHealthData showed 55 minutes of sleep. The owner hadn't worn the watch overnight: it was a nap from 09:32 to 10:27. Coros dates every sleep by the day it ended, naps included, so a daily sleep total mixes the night with naps. A nap could look like a terrible night, or inflate a short one.

querySleepOverview separates them: `Main Sleep (asleep)`, `Main Sleep Period (incl. awake)` and `Main Sleep Window` for the night, and `Naps Total` and `Nap Window` for naps. A day with no night has no Main Sleep lines at all.

Decision (owner, 2 Oct 2026): the sleep signal uses Main Sleep time asleep from querySleepOverview. No Main Sleep means no data. The daily health total is not used for the verdict.

### L24. HRV replies carry Coros's own range and rating

With data, each night reads `HRV Avg: 91 ms — Below normal`, `Normal Range: 93 - 111 ms`, `Baseline: 102 ms`. A missing night appears either as `No data` under its date, or not at all (the assessment simply skips it). The HRV flag compares the average with the range's lower bound, and the parser cross-checks Coros's rating ("Below normal") so a format change shows up as an error.

### L25. Older history uses other formats

The first real 12-week import on 2 Oct 2026 hit three formats the recent fixtures didn't have. Each was logged as "Coros format changed" and none was stored as no data, as designed (L5), but those chunks didn't import:

- **HRV rating "Low"**, a step below "Below normal" (16 Jul: 88 ms against 96 to 108). Now a rating of its own, flagged like Below normal.
- **Legacy sleep, before mid-July:** one `Main Sleep:` figure instead of separate asleep and in-bed figures. It is time in bed; time asleep is Main Sleep minus Awake Time. Checked against Coros's own Daily Sleep on every night with one in July and August: asleep plus naps matches exactly. Legacy naps carry "(includes legacy reported durations)" and a nap window dated 1982, which the app ignores.
- **"Sleep detail for this day is not available yet."** with Sleep Score 0 (29 to 31 Aug): no data. And some nights (26 Jul) have no Daily Sleep line at all; the app doesn't need it.

Each case is now a real-reply fixture with tests. Lesson: one or two weeks of fixtures aren't enough for a format that drifts over time; run the full import against real history early.

### L26. The background job shared the app's database connection

The WorkManager job runs in the app's process, and sqflite keeps one native connection per database file. When the job closed its database, the open app lost its connection ("database_closed") until restarted. The job now opens its own connection.

### L27. Training load history stops at about 31 days

queryTrainingLoadAssessment takes only a "last N days" count, with no date range. Asked for 85 days on 2 Oct 2026, it returned 31 (2 Sep to 2 Oct). Older load can't be fetched, so the app keeps every day it syncs from now on. The M2 weekly review starts with about a month of load history; the 12-week load view fills in over time. The PRD's baseline load figures (the 2.11 spike, Excessive days) came from Coros directly and are still in the fixtures and the PRD.

### L28. Plan workouts show as codes

queryTrainingSchedule names workouts from a Coros training plan with internal codes. On 2 Oct 2026 the owner's "Marathon Plan 430" showed S5715, S5724, S5778 and S5809, which queryTrainingPlanDetails gives as "7k Easy + 6 Strides", "Core Workout" (strength, sport type 4), "6k Easy" and "11k Easy". The plan details also carry each workout's structure (sections, Zone targets), which M3 needs to tell easy days from hard ones.

Effect in M1: Today's workout card shows the code, and a running icon on strength days.

**Fixed on 3 Oct 2026**, as planned. Database version 2 adds the plan link, sport and structure to the schedule, with a tested upgrade from version 1. Original plan: keep the Plan ID internally when parsing the schedule; when a day's workout comes from a plan, also call queryTrainingPlanDetails for that date and take the course name, sport type and structure; show the sport's icon and sport-appropriate advice. Add a fixture from the 2 Oct reply. Standalone (non-plan) workouts are unverified; parse both strictly.

### L29. Lap data is JSON

queryActivityLapData is the one tool found so far that returns structured JSON instead of prose (compare L5, L13). Units: distance in centimetres, time in seconds, pace in seconds per km. Lap group type 2 holds the watch's automatic 1-km splits; a run's last split can be a few metres long and is ignored below 950 m. Strength sessions list every set with `exerciseNameKey` naming the body part ("Legs/Hips"); sets have reps and `sets: 0`, rest intervals have no reps, and two closing laps carry session totals. The app fetches lap data once per run or strength session (about 50 calls for 12 weeks) and records that it has.

On the owner's 30 Sep easy run, every km split averaged 150 to 169 bpm against a 145 cap, which is why the fitness trend usually shows an estimate for now (PRD, Decisions for F3).

### L30. A week in progress is not a short week

On Saturday 3 Oct, the review's load rule said "hold next week at or below this week's 5 km": the 5 km was four days' running, not a week's. Partial weeks now get advice about the rest of the week ("keep the rest of this week easy"), show "so far" with the weekly average instead of a percentage change, and never compare volume. A finished week's ceiling is the recent 3-week average, not its own total. The Sunday 19:00 summary reviews the week as finished.

A second mid-week problem, also found by the owner on 3 Oct: the card said "no hard sessions until it's back to Optimized" while Today showed load already back to Optimized (Excessive Mon to Wed, Optimized from Thursday). Mid-week load advice now follows the latest load day: still Excessive means "keep it easy until it's back to Optimized"; back down means "your load was Excessive on Mon, Tue and Wed and is back to Optimized; train as planned, with an easy day after any hard one". Lesson: two screens reading the same signal must agree; a week summary must not contradict today's state.

### L31. Overflow depends on text size

The owner saw "bottom overflowed by 1 pixels" under the tallest bar. Fixed pixel heights left no room for the phone's text scaling. Bars now take the space left after their labels. The widget tests didn't catch it because Flutter tests draw text in a placeholder font (every letter a full square); they now load Inter Tight and render Today and Week on a 360dp-wide screen at 100% and 130% text, which found two more overflows (a legend line and a header row) before they reached the phone.

### L32. What Coros lets an app change

Checked 5 Oct 2026 from the tool definitions. A training plan created through the MCP (`createTrainingPlan`, 4 to 16 weeks, starting within 14 days) can be edited a day at a time with `updateTrainingPlan`; completed days are locked. A plan built in the Coros app, like the owner's "Marathon Plan 430", can be read but never changed. Standalone scheduled workouts can be created and edited, but not moved or removed. Strength workouts can't be created, only scheduled from the user's library. There's no tool to start a library plan.

So the PRD's "push to watch" and "adjust" only work for plans the app itself creates. For this block (Malnad 50K, 27 Nov 2026) the owner chose to follow their own plan, with the load guard flagging issues and swaps given as advice (PRD, Decisions for F2). The planner and push to watch become a milestone after Malnad.

### L33. Plan workouts carry their structure

Plan details include each workout's sections: distance or time, Zone, interval repeats. The load guard reads those, not names: "7k Easy" on 13 Oct is set to 10 km. A run counts as hard only for a section longer than a minute at Zone 3 or above, so 20-second strides don't make an easy run hard. Time-based parts are converted at the owner's recent easy pace, so planned km are estimates and the Plan screen says so. Running the guard over Marathon Plan 430 on 5 Oct flagged the 15 km to 23 km long-run jump (growth and share of the week), and race week as unplanned (the plan ends 21 Nov, the race is 27 Nov).

### L34. Two testing traps

The screen tests opened an in-memory database and never closed it; sqflite hands back the same open in-memory database, so each test inherited the last one's data (two Malnad goals, a plan on Today). Each screen test now opens its own. Separately, Flutter's debug checks flagged that the Plan screen's expandable week rows sat in a coloured box that hid their tap ripple; they now draw their own surface.

### L35. More "nothing here" replies

Found on the phone, 5 Oct 2026. Two replies were logged as format errors though Coros was only saying there was nothing:

- `queryTrainingSchedule` on a rest day (5 Oct) returns the single line "No training schedule found." with no header.
- `querySleepHrv` for a night with no data at all (4 Oct, watch not worn) replaces the "Sleep HRV Time Series" section with "No sleep HRV time series data found in the last 1 days."

Both are now read as empty and are covered by verbatim fixtures (`training_schedule_none.txt`, `sleep_hrv_no_nights.txt`). Any other wording is still a format error, so L13 holds: only known "nothing" sentences count as no data.

### L36. Guard rules must look past a recovery week

Found running the guard on the phone's database, 5 Oct 2026. Comparing a week with the week before, or with the 3-week average, flagged 26 Oct (back to 54 km and a 22 km long run after the 19 Oct cutback) as a 24% volume jump and an 11 km long-run jump. Both are normal after a recovery week. The rules now compare with the biggest week and the longest run of the previous 3 weeks. This also made the 12 to 18 Oct warning accurate: the owner ran 21 km on 21 Sep, so the 23k is a 3 km step, not 8.

The same run showed the plan stops on Sat 14 Nov while Malnad is Fri 27 Nov, so 16 to 22 Nov has no runs. Only race week was flagged. A new rule flags any empty week before race week; in the taper it suggests about 75% of the peak week.

Owner decision, same day: for trail races longer than a marathon, the long run may be up to 50% of the week (road races keep 35%). With Malnad set, only 9 to 15 Nov (a 17 km run in a 32 km week, 54%) still trips it.

Also worth knowing: planned km include the 5-minute warm-up and cool-down at easy pace, so each run reads about 1.3 km more than the distance Coros shows.

### L37. IFCT 2017: raw ingredients, and a licence change

The Indian Food Composition Tables 2017 list 542 foods per 100 g edible portion, raw: rice, toor dal (as "Red gram, dal"), ghee. There are no cooked dishes, so home food is logged through recipes built from raw grams (owner decision). The npm package `ifct2017` moved to AGPL-3.0 in 2026; the data now comes from `@ifct2017/compositions` 2.0.9, which is MIT. Energy is in kJ and is converted to kcal. IFCT's regional names don't include everyday spellings like "toor", so a small alias list maps them (toor to Arhar). The underlying data belongs to the National Institute of Nutrition; the app uses it privately for the owner only (sole-user decision, L51).

### L38. Active calories from queryDailyHealthData

"Calories" in queryDailyHealthData is active energy, not total: 540 kcal by evening on 5 Oct after a 35-minute session, 303 kcal on a rest day, against a resting energy of about 1,730. The tool only takes `days` (no dates); 40 days worked. The morning check stores the last 2 days, and the Log screen backfills 35 days once on installs from before M4.

### L39. Open Food Facts search

On 5 Oct 2026 the classic `/cgi/search.pl` returned a "temporarily unavailable" page, while `search.openfoodfacts.org/search?q=...` returned JSON hits with nutriments per 100 g. Brands come back as a list. Some products lack calories; the app works them out from protein, carbs and fat. The app sends only the search text, with a User-Agent naming the app.

### L40. Macro rules versus a weight-goal deficit

With the PRD defaults, an easy day for the owner (about 460 active kcal) needed at least 2,590 kcal: 126 g protein, 393 g carbs (5 g/kg) and fat at 20% or more. Maintenance is about 2,190, so the 500 kcal deficit vanished and the target sat 400 above maintenance. The owner chose "calories win": on deficit days carbs shrink to fit, never below 3 g/kg, giving about 1,810 kcal and a 385 kcal deficit on an easy day. Hard and long days stay fully fuelled.

### L41. Editing Dart from Python, again

Two more edits went wrong the same way as before: an escaped newline pair inside a Python string became real line breaks in a Dart string, and the backslash before the apostrophe in "Today's meals" was lost. Python treats backslashes in ordinary strings as escapes, so they never reach the file. Rule: any Dart string content goes through the Edit tool, never through Python or shell strings. (This very entry was mangled the same way when first written.)

### L42. Manual entries need estimates

The owner's first three manual entries on 5 Oct 2026 were guesses that didn't add up: "Rice + Chapati" at 600 kcal with 600 g carbs (the macros alone are about 2,600 kcal), and "Guava" at 100 kcal with 100 g carbs (about 410). People rarely know calories for a fruit or a plate of food. The manual entry now offers estimates from USDA FNDDS survey foods (5,431 foods, public domain), which include fruits and many Indian dishes (Dal, Idli, Dosa, Bread chappatti or roti, Upma, Sambar, Biryani) with household portions such as "1 fruit, 55 g" or "1 medium chappatti, 40 g". A name like "rice + chapati" is split into parts, each estimated separately and summed. Before logging, the app checks that calories and macros roughly agree (4, 4 and 9 kcal per gram) and asks once if they don't. FNDDS is US recipes, so values are labelled a rough guide. Some foods are missing (poha); then the numbers are typed. First real use showed USDA spellings matter: plain tofu is "Soybean curd" and sourdough is filed under "Bread, French or Vienna", so tofu and sourdough are now aliases.

### L43. IFCT has no energy value for oils and ghee

Found on the phone, 5 Oct 2026: the owner's "Horse gram saaru" recipe used 10 g coconut oil at 0 kcal, missing 90 kcal. In the IFCT data all 14 fats (T001 to T014, including ghee) have energy 0 despite 100 g fat per 100 g, and two foods are off by more than half (chicken leg, skinless: 384 against 192 from its macros; crab Q001). For these 16 the energy is recomputed from the macros (4, 4 and 9 kcal per gram, 2 for fibre). Smaller gaps, mostly vegetables, are left as IFCT gives them. On app start the Log screen updates IFCT foods already stored on the phone and recalculates recipes that use them; meals already logged keep the values they were logged with.

### L44. Snackbar with an action stays on screen

In Flutter 3.47, a SnackBar with an action (Undo) persists until tapped unless `persist: false` is set. The owner saw the "Removed" message stuck. Fixed, with a screen test that fails on the old behaviour.

### L45. Saved meals and typed-in entries

The owner tried saving a meal made of typed-in entries and nothing was saved: the app only saved items linked to a food. Since manual entry is the owner's main way of logging, a typed-in entry is now stored as a hidden food (kept out of search and recents) so a saved meal can log it again.

Also seen: "Rice, raw, milled" logged at 100 g (356 kcal). IFCT values are for raw food; cooked rice is about a third of that per 100 g. Owner decision: USDA foods now also appear in the main search as "Cooked & common", above IFCT, so cooked foods are found first.

### L46. Two checks at once

On 6 Oct 2026 at 06:39 the owner tapped Check now while the background morning check was running. Both fetched the same Coros replies within the same seconds, and each runs on its own database connection (L26), so one write met the other's lock and failed at once with "database is locked (SQLITE_BUSY)". The second tap worked. The same overlap happened on 7 Oct without an error. Fixes: every connection waits up to 10 seconds for a lock (`PRAGMA busy_timeout`), and a lease stored in the database lets only one check run at a time. Check now during a background check waits for it and shows its result; a background check during Check now skips. A lease expires after 3 minutes in case the app is killed mid-check.

### L47. Fibre target

The owner asked for fibre beside protein, carbs and fat. The PRD had no fibre target; the app uses 14 g per 1,000 kcal of the day's target, the US Institute of Medicine adequate intake (about 25 to 47 g a day for the owner). The Log card now shows four tiles, two by two, because four in a row cut off "Protein" at large text on a 360dp phone. Fibre is teal, as in the reference designs; sky would sit too close to fat's blue.

### L48. FIT files and their links

Checked 7 Oct 2026 with the owner's run that day: queryActivityFitFileDownloadUrls returned `https://s3.coros.com/fit/<user>/<labelId>.fit`, and a plain GET with no token downloaded it (89 KB). The file holds 2,101 record messages, 2,093 with a position (one a second), plus heart rate, distance and running dynamics. The app decodes only positions, with its own small FIT reader that matches the Python fitparse library point for point. Because the link works for anyone who has it, the app fetches files straight to the phone and never logs or shares the address. Each link counts against Coros's 50 FIT files a day; the app uses at most 40.

### L49. How far back history goes

querySportRecords returns newest first, and its header counts only the records returned, so it can't say how many exist. The owner's history starts in 2025: a query for 2010 to 2024 returned the single line "No sport records found from 2010-01-01 to 2024-12-31." (another "nothing here" wording, like L35). The app probes a year at a time back from last year, stops at the first empty one, then imports month by month.

### L50. CARTO tiles need a key

On the owner's first look at the map (7 Oct 2026) every tile read "API KEY REQUIRED, carto.com/basemaps/apikey". CARTO now serves a watermark image (HTTP 200, ETag starting "wm-") to requests without a key; keys registered before 23 September 2026 keep working. A key is free, needs no account and arrives by email; non-commercial use is free up to 5M requests a month (commercial free up to 1M). The URL also moved: `https://basemaps.cartocdn.com/rastertiles/dark_all/{z}/{x}/{y}.png?key=KEY`. The app takes the key in Settings (Run map, Dark map key) and stores it with the other settings. Without a key it uses OpenStreetMap's standard tiles darkened on the phone, which suits a single personal user under OSM's tile policy but not a public app.

### L51. Sole user

Owner decision, 7 Oct 2026: the app is for the owner alone. It won't be shared with friends, listed on the Play Store or made commercial. What this removes from the PRD: stages 2 (friends, Play Console testing) and 3 (Play Store, iOS); the Play Data safety form, health apps declaration and privacy policy; the crash reporter planned before friends joined; and the open questions about map tile, IFCT and Open Food Facts terms for public use (personal, non-commercial use fits all of them). What stays: everything on the phone and in the owner's own Drive, tokens in Keystore, the local error log, and the Google consent screen question (publishing it only stops the 7-day backup sign-in expiry; it doesn't make the app public). The per-install unique Coros client name (L7) stays too: it costs nothing and keeps a reinstall from colliding with an old registration.

### L52. A first screen that says where you stand

Owner feedback, 7 Oct 2026: Today showed the verdict and four signals Coros already has, so it wasn't insightful. Home now leads with goals, each with a rule-based status and reasons, then the week so far, then insights that apply, then today's call. Run against the owner's real data the same day it said: Malnad 51 days out, Watch, because the plan's longest run is 24 km against the first-50K guidance of 2 or 3 runs around 32 km (or 4 hours) by 13 Nov, the plan has no trail runs, and this week's planned volume is 29% over the biggest recent week; runs over the last 2 weeks were ahead of plan (42 km against 38). The benchmark is generic guidance with sources, labelled as such, not a judgement of the owner's Coros plan. Owner feedback on the first version: too verbose. Home now draws each goal (race: countdown, a block bar with today and the taper, plan %, long-run dots, longest run against 30 km; weight: current to target bar and a sparkline; consistency: dots per session) with one short line, and the full reasons moved to Plan, "Where you stand".

### L53. The FIT limit is a rolling 24 hours

From 8 Oct 2026 the error log filled with "You have reached the daily limit of 50 activity FIT files", every 15 minutes, for two days. The app counted its 40 a day per local calendar day, but Coros counts 50 over a rolling 24 hours: 49 links fetched between 14:00 and 23:30 UTC on 8 Oct kept the limit closed until the same hours on 9 Oct, while the app's own count had reset at midnight IST. The app now counts the links it fetched in the last 24 hours (from the stored replies), and after a limit error it stops asking until the oldest of those is 24 hours old (or 4 hours if the limit came from elsewhere, such as Claude's own test calls on the same account). Routes still progressed: 134 of 182 by 10 Oct.

### L54. No timeouts on Coros calls

The owner reported endless loading on 10 Oct. Every screen's data loaded from the phone's database in under half a second on a copy, and the app logged nothing. The likely cause: none of the HTTP calls to Coros had a timeout. A dropped connection (one "Software caused connection abort" was logged on 9 Oct) can leave a request waiting forever; a hung token refresh blocks every Coros call behind it, a hung background check holds the one-check-at-a-time lease, and Check now waits on it. MCP calls now time out after 30 seconds and sign-in requests after 20. Each screen's load also fails after 20 seconds with a message and an error-log entry (with the time it took), so a hang can't be silent again.

### L55. Two connections, one thread: the endless loading

13 Oct 2026: endless loading again, no check that morning, and nothing in the error log. Android showed the background job as still "RUNNING", and the old build's last run failed with "database is locked ... while compiling: PRAGMA journal_mode". The cause: sqflite on Android runs every database operation on one native worker thread (THREAD_COUNT = 1). Since L26 the background job opened its own connection to the same file, and since L46 every connection waited up to 10 seconds for a lock. When the job held a write lock, any query from a screen waited on the lock while occupying the only thread, and the job's next statement (the one that would release the lock) queued behind it: every screen query stalled 10 s and failed, and even writing the error to the log failed, so nothing was recorded; the job itself hung until Android stopped it. L54's timeouts were real gaps but not this one.

Fix: the background job uses the app's shared connection (sqflite then queues each side's statements around the other's transactions), never closes it (L26), and there's no busy wait. Background failures and runs over a minute now go to the error log, and a run is cut off at 8 minutes, before Android's 10.

### L56. A public repo from a personal project

13 Oct 2026, preparing to publish on GitHub. A scan found more than tokens: the real FIT file traced a run from the owner's front door; activity start points sat at both homes; a saved Coros link held the owner's user ID (and since FIT links need no login, user ID plus activity ID would let anyone download routes); the profile reply held a birth date; and the Google OAuth client ID sat in code. Fixes: every fixture coordinate moved +0.5 degrees (tests updated, all still pass), the FIT file rebuilt from the real track as a minimal valid FIT with moved positions, the user ID zeroed, the birth date changed, and the client ID read at build time from git-ignored `app/dart_defines.json`. Kept out entirely by `.gitignore`: the signing key and memory notes (`mac-migration/`), third-party design mockups, phone logs and database copies. Real health numbers (HRV, sleep, weight) stay: they're the story, and the owner chose to share them.

## Changes needed

### PRD edits

| Section | Current text | Change |
| --- | --- | --- |
| Coros sign-in without a server, step 1 | "Each install gets its own client ID." | Coros reuses the client ID for a repeated `client_name`, so each install registers under a unique name, for example "Training Companion · a1b2c3d4" (L7). |
| Coros sign-in without a server | "The metadata doesn't list secret-less clients, but the CLI registers one" | The metadata lists `none`; secret-less clients are supported (L10). |
| Sign-in path table, path 1 | "Coros may accept only http redirects" | Confirmed: custom schemes are rejected. Path 1 works only as an https App Link, which needs a domain serving `assetlinks.json`. Loopback becomes the main path (L2). |
| Sign-in paths | (not mentioned) | Note that the advertised device flow is closed to self-registered apps (L3). |
| Data sources, constraints | (not mentioned) | Add: tool results are prose written for AI assistants, so each tool needs a strict parser, and a format change is a sync error, not missing data (L5, L6). |
| Data sources, constraints | (not mentioned) | Add: refresh tokens rotate on every refresh (L4). |
| Technical approach, risks | "Coros MCP is new and changing" | Expand: replies are free text with no version and no structured alternative (checked 2 Oct 2026), so wording changes can break parsing silently; mitigated by strict parsers, saved real replies as test samples, and stored raw text (L5, L13). |
| Core logic, morning verdict table | Resting HR source: queryRestingHeartRate | Keep, and add that the daily health header value is not used because it changes during the day (L15). |
| Privacy and data handling | (not mentioned) | Add: GPS coordinates are kept for the planned run map, on the phone and in the user's own Drive only; the CSV export says it includes them (L16). Owner decision, 2 Oct 2026. |
| Privacy, Coros tokens | "revoked on disconnect" | Done in PRD v0.2: revocation fails for public clients (L12), so disconnect deletes tokens from the phone, tokens never leave Keystore, and the user is told how to remove access on the Coros side. |
| Open questions | Spike: confirm Coros accepts the app's sign-in | Mark the Coros side as passed from the laptop (L1); the Android side is still open. |

### App design changes (from M1 on)

1. **Coros layer**
   - One parser per tool, all in the isolated Coros module.
   - Parsers are strict: a missing label or a non-number raises a "Coros format changed" error. Never fall back to "no data".
   - Keep "Coros says No data" (a normal no-data day) separate from "couldn't read the reply" (an error), all the way to the verdict (L5, L8).
   - Each reply's text is a JSON-encoded string: decode it once, then parse the prose (L13).
2. **Raw replies stored.** Save each raw Coros reply in SQLite next to the parsed values, so a fixed parser can re-read history without fetching again (L5).
3. **Parser tests.** Save real replies from the owner's account, including no-data replies, as test samples. Unit-test each parser against them (L5, L8).
4. **Visible parse errors.** A parse error goes to the local error log and shows a banner on Today. The verdict for that day shows the affected signal as an error, not as missing (L5).
5. **Client registration.** Register once on first run with a unique name. Store the client ID in secure storage with the tokens. Re-register only if Coros rejects the stored ID (L7).
6. **Token storage.** Tokens can't be revoked (L12), so they never leave Android Keystore: excluded from the Drive backup and the CSV export.
   **Refresh handling.**
   - Write a refreshed token pair in one atomic step.
   - Only one refresh at a time across the app and background workers (a lock).
   - Refresh well before the 30-day expiry (L4).
7. **Sign-in port.** Ask Android for any free port at sign-in time (L14).
8. **Dates.** `queryUserInfo` doesn't return a timezone (checked 2 Oct 2026), so use the phone's zone with a setting to override. Query by that date, treating sleep and HRV as wake-up-day values (L9).
9. **Workout IDs.** Pull the Workout ID out of create replies with a pattern, store it, never show it, and ignore any other text in the reply (L6).
10. **Signal sources.** Where two tools disagree on whether a value exists (resting HR in L8), decide which tool is the source of truth for each signal and record that choice in the rules shown in Settings.
11. **Resting HR.** Use queryRestingHeartRate as the source for the morning signal. If it has no value, treat the signal as no data rather than falling back to the daily health header, which changes during the day (L15). Revisit after a week of real mornings.
12. **Location.** Keep GPS coordinates; the owner wants a run map (2 Oct 2026). They stay on the phone and in the user's own Drive backup, and the CSV export says it includes them (L16).
13. **Activity IDs.** Use `LabelId` as the activity's key, so re-syncing a month never creates duplicates (L17).
14. **Background network.** All Coros calls outside the foreground run as WorkManager jobs with a network constraint. Sign-in swaps the code only once the app is in front (L20).
15. **Single screen instance.** Keep `singleTask`, recheck state on resume, and resolve L21 before building the sync worker.

### Still to test in M0

- [x] Whether Coros sends `structuredContent` or an `outputSchema` (L13). It doesn't.
- [x] Sign-in on an unregistered loopback port (L14). Works.
- [x] Token revocation with no client secret (L12). Doesn't work.
- [ ] Whether the Coros app lets a user see and remove authorised apps (L12). Owner to check in the app.
- [ ] Before M5: download one FIT file and confirm it carries the GPS track (L18).
- [x] Everything on Android: build, sign-in from the phone with the listener alive behind a Custom Tab, data reads, a workout write, and the home screen widget (L19 to L22).
- [x] Start of M1: find why a second screen instance appears after sign-in (L21). Flutter's built-in deep linking; turned off.
