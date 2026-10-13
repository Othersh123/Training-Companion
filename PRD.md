# Training Companion PRD

7 Oct 2026 · Draft v0.4 (sole user: no friends, store or commercial use; M0 to M5 findings in [learnings.md](learnings.md))

> **How to build:** work through the milestones in order, one at a time. After each one, stop, report what was built and tested, and wait for the owner to say whether to continue.

## Overview and problem

Training Companion is a personal Android app, built for the owner as its only user, that turns Coros watch data into four things: a daily readiness verdict, a training plan pushed to the watch, a weekly review, and a food and body log. Coros is the single source of truth. Coaching runs on fixed, transparent rules, not AI.

A 12-week review of the owner's Coros data (6 Jul to 30 Sep 2026) shows the problems the app must fix:

- **Load spikes.** Two long runs a week apart pushed the Coros load ratio to 2.11, flagged Excessive for 4 days.
- **Easy runs run too hard.** 7 of 18 runs on the home 5k loop averaged 155+ bpm, one of them three days after a half marathon.
- **Strength fades when mileage peaks.** About 2 sessions a week in July, then 0 or 1 a week from August to mid September.
- **Spiky volume.** Weekly running swung between 5 and 34 km, with no steady base.
- **No food or weight data.** Coros records neither, so diet and physique goals can't be tracked.

The Coros app already shows most of these numbers. What's missing is a verdict on what to do today, a plan that enforces the fixes, and a weekly check against a goal.

## Goals and non-goals

**Goals**

1. Tell the user each morning whether to train as planned, go easy, or rest, and say which signals drove that call.
2. Build a training block toward a goal and push its workouts to the Coros watch, with heart-rate caps on easy runs and strength sessions on the calendar.
3. Review each week against the goal: volume, load, easy-run compliance, strength, aerobic fitness, sleep, weight and macros.
4. Log meals, macros and body weight, and set food targets by how hard each day's training is.
5. Support four goal types at launch: race finish time, body weight, consistency, and aerobic fitness.
6. Later (M5): show everywhere the user has run on a map, framed on India with a world view.

**Non-goals for v1**

- AI coaching or AI-generated plans. All decisions come from fixed rules the user can read.
- Meal photo logging. Dropped for v1; may return later.
- Data from Strava or other platforms. Coros only.
- Social features, leaderboards or sharing.
- Other users. The owner is the only user: no friends, no store listing and no commercial use (owner decision, 7 Oct 2026).
- iOS. The owner uses Android.
- Medical advice. The app gives training and nutrition guidance only.

## Target user

The owner is the only user, now and later (owner decision, 7 Oct 2026). The app is installed directly from the build on the owner's phone. It won't be shared with friends, listed on the Play Store or used commercially, so there are no store declarations, privacy policy, multi-user support or commercial terms to meet.

The owner's profile, for reference: male, 31, 175 cm, 78.6 kg, based in Bangalore. Runs 3 to 4 times a week, half marathons, does strength 0 to 3 times a week, travels often (including altitude trips).

## Data sources and Coros integration

The app connects to the official COROS MCP at `https://mcp.coros.com/mcp`. Coros lets developers build single-user apps on it with standard OAuth 2.0, self-service, with no application or approval needed ([Build on COROS MCP](https://support.coros.com/hc/en-us/articles/53181619102996)). The Partner API isn't an option: it requires a registered company with an established user base ([Partner API Access](https://support.coros.com/hc/en-us/articles/53181766856724-Partner-API-Access)).

**Constraints that shape the design**

- **No webhooks.** The app must poll Coros to find new sleep and activity data.
- **Single user per authorization.** The app signs in to the owner's own Coros account, which is exactly what Coros supports for self-service MCP apps.
- **FIT files capped at 50 a day per account.** The app uses summaries and lap data, and fetches FIT files only when needed.
- **Large queries fail.** A 3-month activity query returned an error during testing; one month at a time worked. Sync pages by month.
- **Gaps in daily data.** Resting HR or sleep is missing on some days (travel, watch off). Every rule needs a no-data path.
- **Phone sign-in needs no server.** Coros's own official CLI registers itself without a client secret, signs in with PKCE and refreshes tokens, all on the device. The Android app follows the same pattern. The M0 spike proved the full flow against the owner's account from a laptop on 2 Oct 2026, including sign-in on an unregistered loopback port; it hasn't been tried from an Android phone yet.
- **Results are text written for AI assistants.** Every tool returns a prose report (for example `Load Ratio: 1.32`), wrapped as a JSON-encoded string, with no `structuredContent` and no `outputSchema` (checked 2 Oct 2026). Some replies also contain instructions aimed at an AI, which the app ignores. Each tool needs a strict parser, and a reply the app can't read is a sync error, never "no data".
- **Refresh tokens rotate.** Every refresh returns a new refresh token and invalidates the old one, so the app saves each new pair in one atomic step and never runs two refreshes at once. Access tokens last 30 days.
- **Dates are in the user's Coros timezone.** Sleep and HRV are dated by the morning the sleep ended, so last night's values are under today's date. The app queries by the Coros date, not the phone's UTC date.

Checked against the owner's account on 2 Oct 2026:

- **HR zone values can't be read.** No tool returns zone boundaries. Workouts can still target a Coros zone (1 to 6), a percentage of threshold HR, or a bpm range, and the watch applies the user's own zones.
- **Strength workouts can't be created.** The MCP creates only running, cycling and trail running workouts.
- **Strength body parts are recorded.** Lap data for a strength session lists the body part for each set, for example Legs/Hips.
- **Activities carry stable IDs and locations.** Each record has a numeric `LabelId`, Unix start and end timestamps, a numeric sport type code, a location name (for example "Bangalore Run") and, for outdoor activities, GPS start coordinates. The app keys activities by `LabelId` so re-syncs never duplicate them.
- **Resting HR has one reliable source.** queryRestingHeartRate gives the daily value. The resting HR shown in the queryDailyHealthData header changes during the day (58 then 49 bpm on the same afternoon), so the app doesn't use it.
- **Workout writes work.** createSingleWorkout saved an easy Zone 2 run to the owner's library and returned a Workout ID, which the app stores to schedule or edit the workout later.

**Data the app uses (confirmed working on the owner's account)**

| Data | Coros MCP tool | Used by |
| --- | --- | --- |
| Sleep HRV, baseline and normal range | querySleepHrv | Morning check |
| Resting heart rate | queryRestingHeartRate | Morning check, weekly review |
| Last night's main sleep, separate from naps | querySleepOverview | Morning check, weekly review |
| Steps, stress, daily sleep incl. naps | queryDailyHealthData | Weekly review |
| Short- and long-term load, ratio, Coros label | queryTrainingLoadAssessment (recent days only, about 31 at most; the app keeps each day it syncs) | Morning check, load guard, weekly review |
| VO2max, threshold pace, race predictions | queryFitnessAssessmentOverview | Goals, weekly review |
| Activities: type, distance, time, pace, avg HR, strength sets | querySportRecords | Weekly review, compliance |
| Laps and activity detail | queryActivityLapData, getActivityDetail | Aerobic fitness trend |
| Profile: height, weight, age | queryUserInfo | Setup, food targets |
| Create and schedule workouts | createSingleWorkout, createScheduledWorkout, scheduleWorkout | Training plan |
| Create, update and browse plans | createTrainingPlan, updateTrainingPlan, queryTrainingPlanLibrary | Training plan |
| Strength sets and body part worked | queryActivityLapData | Weekly review |
| Activity start point and location name | querySportRecords | Run map pins |
| GPS route of an activity | downloadActivityFitFiles or queryActivityFitFileDownloadUrls (50 a day). getActivityDetail has no track points (checked 2 Oct 2026) | Run map routes |

**Other sources**

- **Body weight:** manual entry. The owner's scale has no app. Health Connect import can be added later if the owner gets a smart scale.
- **Food:** manual entry only in v1. Nutrition values come from a mix: the Indian Food Composition Tables (IFCT 2017, 528 foods), Open Food Facts for packaged foods, and the user's own entries.

## Features

Build order follows the owner's priority: morning check first, then weekly review, training plan, food and body log, and the run map last. The owner confirmed this order.

### F0. Home: where you stand (added 7 Oct 2026)

The first screen. The owner found the verdict-only Today screen repeated what Coros shows, and asked for status against goals instead. Owner decisions, 7 Oct 2026: goals first, a this-week strip and insights; today's fuel stays on Log; the signal tiles fold behind the verdict; the tab is called Home.

- **Visual, not verbose (owner, 7 Oct 2026):** Home draws each goal (a big number, progress bars, dots) with one short line; the full reasons are on the Plan tab under "Where you stand", and tapping a goal opens Plan. Insights are chips; tapping one shows the full sentence.
- **Goal cards,** primary first, each with On track, Watch or Off track, always labelled, and the reasons:
  - **Race:** days to go and the taper date; plan adherence over the last 14 days (runs and km done against planned; under 80% is Watch, under 60% Off track); a long-run benchmark where a sourced one exists (first 50K: 2 or 3 runs of about 32 km or up to 4 hours on trails, the last about 2 weeks out, counted from 30 km; sources: Marathon Handbook, Hal Higdon's 50K plan, Jeff Browning's 50K plan); trail runs missing before a trail race; the nearest load guard warning.
  - **Weight:** the 7-day average, kg to go, the rate needed (flagged when over 1 kg a week), and the 3-week trend with a projected date once 3 weigh-ins span a week.
  - **Consistency:** this week's runs and strength sessions against target, with days left.
  - **Aerobic fitness:** easy-HR pace now against 6 weeks ago.
- **This week so far:** km, runs and strength against the plan, easy runs under the cap, the long run still to come, and one drift flag (Excessive load days or volume over 10% above the 3-week average).
- **Worth knowing,** only when it applies: HRV below range on 3 of 7 nights (or the 7-night average under 93% of baseline), 3 or more short nights in 7, resting HR 3+ bpm above the previous 30 days, no strength in 14 days, and a long or hard run tomorrow.

### F1. Morning check (build first)

Each morning the app gives one verdict, **Go as planned**, **Go easy** or **Rest**, and lists the signals behind it.

- Starts polling Coros at a user-set wake time and checks every 15 minutes until last night's sleep and HRV appear, for up to 2 hours.
- Sends a notification once the data has synced. If nothing syncs within the window, it sends a fallback notification that says what's missing. A Check now button on the Today screen and the widget polls Coros again at any time.
- Shows the verdict on a home screen widget, with the signal that drove it and today's planned workout.
- Lists each signal with today's value, the user's normal range, and whether it's in range: HRV, resting HR, sleep duration, load ratio.
- Flags yesterday's easy run if its average HR went over the cap.
- When a signal has no data, says so and decides from the rest. With fewer than 2 signals, shows "Not enough data" instead of a verdict.
- If the verdict is Go easy or Rest and a hard workout is scheduled, offers to swap it for an easy run or rest in Coros. Never changes the plan without the user's tap.

### F2. Training plan to watch

The user picks a goal, then either starts from a Coros plan or lets the app build one from rules. Either way, the workouts go to the watch.

- **Goal setup.** Goal type: race, weight, consistency, or aerobic fitness. For a race, the user enters the race date and distance, and a target time if they want one. Several goals can be active, one marked primary.
- **Two ways to start.** Browse the Coros plan library and adopt one, or have the app build a plan from the goal, race date, the last 4 weeks of volume, and the user's HR zones.
- **Easy runs carry an HR cap.** Workouts target the user's Coros Zone 2, so the watch alerts them against their own Coros zones.
- **Strength sessions are scheduled.** Count per week is set by the user, default 2. Coros can't create strength workouts, so these stay in the app's plan as reminders, not on the watch.
- **Load guard.** Before the user saves a plan or week, the app warns if the planned load would likely push the Coros load ratio into Excessive.
- **Push to watch.** Scheduled workouts go to Coros, and the watch picks them up on its next sync.
- **Adjust.** Missed sessions and Rest verdicts move or drop workouts. The user confirms each change.

**What Coros allows (checked 5 Oct 2026)**

- A plan created through the MCP (`createTrainingPlan`, 4 to 16 weeks, starting within 14 days) can be changed later, a whole day at a time (`updateTrainingPlan`); completed days are locked. This is how app-built plans reach the watch and how swaps and missed sessions are handled.
- A plan built in the Coros app can be read but **never changed** through the MCP.
- Standalone workouts can be created on a date, but **not moved or removed** through the MCP.
- Strength workouts can't be created, but a strength workout already in the user's Coros library can be scheduled.
- There is no MCP tool to start a Coros library plan; the user starts it in the Coros app and the app follows it.

**Decisions for F2 (owner, 5 Oct 2026)**

- **Current goal:** Malnad 50K, a 50 km trail ultra on Friday 27 Nov 2026, run to finish (no target time).
- **This block follows the owner's Coros-app plan, "Marathon Plan 430"** (1 Oct to 21 Nov). The app reads it, runs the load guard over it, and flags risky weeks with a suggested change the owner makes in the Coros app. Easy runs are labelled from the plan. Swap and adjust are advice only, since the app can't change this plan.
- **Taper for the 50K:** 2 weeks, as for the half marathon: the 7 days before race week at about 75% of peak week, and race week at about 50%.
- **The rule-based planner and push to watch move to their own milestone after Malnad.** M3 covers goals, the Plan screen, the load guard, plan-based easy-run labels, swap advice, goal progress and the threshold retest reminder.

### F3. Weekly review

Every Sunday evening the app sends a summary and updates the dashboard.

- **This week against plan:** km run, longest run, sessions done against planned, strength sessions done against planned, with the body parts worked when Coros records them.
- **Easy-run compliance:** the share of easy runs whose average HR stayed under the cap.
- **Load:** daily load ratio for the week with the Coros label, and days spent in Excessive.
- **Aerobic fitness:** pace at a fixed HR band on easy runs, as a trend over 12 weeks. Altitude and trail runs are excluded.
- **Recovery:** average sleep, nights under 6 hours, resting HR trend.
- **Body and food:** 7-day average weight against the goal, and days logged with protein and calories against target.
- **Goal progress:** for each active goal, where you stand and the trend.
- **One thing to change next week,** picked by rule from the weakest metric.
- Includes the 12-week baseline view as the starting history.

**Decisions for F3 (owner, 3 Oct 2026)**

- **Week:** Monday to Sunday, as in Coros. The summary notification arrives **Sunday at 19:00**, editable in Settings.
- **Aerobic fitness:** the median pace of 1-km splits whose average HR is between the cap minus 10 and the cap (135 to 145 bpm for the owner), from easy runs. With fewer than 3 such splits in a week, the app shows an estimate from that week's pace-against-HR line at the cap, labelled "estimated". Splits come from queryActivityLapData, which returns JSON.
- **Which runs count for fitness:** outdoor road runs starting within 25 km of home (the most common start point). Trail, treadmill and travel runs (altitude, coastal heat) are excluded.
- **One thing to change, in priority order:** (1) any day in Excessive load, or weekly volume more than 10% above the previous 3 weeks' average: hold or cut volume; (2) easy-run compliance under 80%: slow the easy runs; (3) fewer strength sessions than planned: book them; (4) 2 or more nights under 6 hours: protect sleep. If none applies, keep going as planned.
- **Planned sessions** come from the Coros calendar (with plan workouts resolved, L28). With no plan, the strength target is the default 2 a week.
- **Strength body parts** come from each strength session's sets in queryActivityLapData (for example Legs/Hips).
- **Load history** starts about a month back (L27) and fills in from here.

### F4. Food and body log

Manual logging of meals, macros and morning weight, with targets that move with training.

- **Meal entry:** food name, portion, calories, protein, carbs, fat. Foods can be searched in IFCT 2017 and Open Food Facts, or typed in. Saved meals and recent foods can be logged in one tap.
- **Daily totals** against targets, shown as protein, carbs, fat and calories.
- **Targets by day type.** Rest, easy, and hard or long days each get their own carb and calorie target. Protein stays constant. Day type comes from the plan, or from Coros if a workout was done without a plan.
- **Morning weight** entered by hand. The trend shows a 7-day average so daily swings don't mislead.
- **Under-fuelling flag.** Raised in the weekly review when a heavy training week lines up with intake under target and worsening recovery signals.
- Targets start from defaults and are always editable. Every target is labelled as an estimate wherever it appears, with a note that it's general guidance, not medical or dietetic advice.

**Decisions for F4 (owner, 5 Oct 2026)**

- **Home-cooked food:** a recipe builder. A dish is built once from IFCT ingredients in raw grams, split into servings, and logged by the serving. IFCT lists raw ingredients, not dishes. A one-off meal can also be typed in by hand (not saved as a food).
- **Meals:** Breakfast, Lunch, Dinner, Snacks and Run fuel (gels and drinks around runs).
- **Packaged foods:** Open Food Facts, searched online (only the search text is sent). A food once logged is kept on the phone. No barcode scanning in v1.
- **Weight goal deficit:** only on rest and easy days, never on hard or long days, and never from 2 weeks before a race to 1 week after.
- **Calories win on deficit days:** carbs shrink to fit the calorie target, never below 3 g/kg. Without this, 5 g/kg carbs on an easy day left no deficit at all.
- **Active calories** come from queryDailyHealthData's "Calories", which is active energy, not total. For today the app uses Coros's figure so far or the median for that day type over 4 weeks, whichever is higher.
- **Profile** (height, weight, age, sex) comes from queryUserInfo. Logged weight (7-day average) replaces the Coros weight once there is some.
- **USDA foods in the main search (owner, 5 Oct 2026):** a "Cooked & common" section and filter chip, above IFCT (raw ingredients). Each result shows calories for a whole-item portion, and the detail screen offers the food's household portions.
- **Manual entries get estimates (owner, 5 Oct 2026):** matching foods from USDA FNDDS (public domain, with household portions) fill in calories and macros, one per item in the name ("rice + chapati"). Values stay editable, and the app warns once when typed macros don't add up to the calories.
- **IFCT data:** the @ifct2017/compositions npm package 2.0.9 (MIT; later versions are AGPL). The data itself is from NIN; the app uses it privately, for the owner only, and doesn't redistribute it.

### F5. Run map (later, M5)

A map of everywhere the user has run, framed on India by default, with the whole world one tap away. Requested by the owner on 2 Oct 2026; all choices below confirmed by the owner the same day.

- **Where it lives.** A Places card on the Week screen shows a small map preview and opens the full-screen map. The map has India and World buttons at the top: India frames the country, World zooms out to every activity.
- **What's on it.** Every outdoor activity with GPS: runs, trail runs, hikes, walks and rides. Pool swims and indoor sessions have no GPS and are left out. Each type has its own colour. Runs only are shown by default; a filter adds the other types.
- **Zoom levels.** Zoomed out, activities show as clustered pins with a count. Zoomed into a city, they become route lines, so a circuit or trail is drawn as it was run. Tapping a route shows date, distance, pace and average HR, and opens that activity.
- **History, filled in gradually.** Start-point pins for the whole Coros history appear straight away, because the activity list carries a start point for each one. Full route lines need each activity's GPS track, which comes only from its FIT file (capped at 50 a day per account); activity detail has no track points (checked 2 Oct 2026). Routes are fetched newest first, inside a daily budget that always leaves room for the morning sync, and the map shows progress, for example "Routes loading: 120 of 340".
- **Home privacy zone.** The user sets a home point (the app suggests the most common start point) and a radius, default 300 m, editable. Route sections inside the zone are hidden on the map, and pins inside it are not shown at the exact spot. The zone changes only what the map draws; stored data is unchanged.
- **Dark map.** Map tiles use a dark style that matches the app: black background, quiet grey roads and labels, routes in the accent colours.
- **Works offline for what's stored.** Routes and pins come from the local database, so they show without a connection. Map tiles need a connection; offline tiles are out of scope.

**Decisions for F5 (built 7 Oct 2026)**

- **FIT files carry the track (checked 7 Oct 2026):** a 35-minute run's file is 89 KB with 2,093 GPS points, one a second. The app reads only the positions, simplifies each route to within 5 m (a few hundred points) and stores it compactly.
- **The download link is a plain S3 address with no login.** The app fetches it straight to the phone and never shares it.
- **History:** the app finds the first year with activities (the owner's starts in 2025) and imports the whole list a month at a time, for start pins.
- **Route budget:** at most 40 FIT downloads a day, of Coros's 50. The background job adds up to 5 routes a run; opening the map adds up to 10. A failed file is retried after a week.
- **Map:** flutter_map with CARTO "Dark Matter" tiles (OpenStreetMap data, attribution shown). CARTO now needs a free key (L50), pasted in Settings; without one the app uses OpenStreetMap tiles darkened on the phone. Routes draw from city zoom (about 11.5); below that, clustered pins.
- **Home zone:** suggested at the most common start, 300 m; long-press the map to move it; radius in Settings, 0 turns it off. Pins inside it are drawn at a fixed offset from home.

## Core logic and rules

Every decision comes from rules the user can read in Settings, along with the numbers that triggered it. All thresholds below are **confirmed by the owner on 2 Oct 2026**, and each is editable in the app.

### Morning verdict

Each signal is either flagged or clear.

| Signal | Flagged when | Source |
| --- | --- | --- |
| HRV | Last night is below the Coros normal range | querySleepHrv |
| Resting HR | 5+ bpm above the 30-day average | queryRestingHeartRate only; the daily health header value changes during the day and isn't used |
| Sleep | Under 6 hours asleep in last night's main sleep (naps excluded) | querySleepOverview `Main Sleep (asleep)`; no main sleep means no data |
| Load | Coros label is Excessive | queryTrainingLoadAssessment |

- **0 flags:** Go as planned.
- **1 flag:** Go easy. Keep the session, cap the heart rate, cut intensity.
- **2+ flags:** Rest, or 20 to 30 minutes very easy.
- **Fewer than 2 signals have data:** no verdict. The app shows what's missing.

The app uses the Coros load label as given, rather than recomputing it. In the owner's data, a ratio of 1.38 was labelled Optimized and 1.65 Excessive.

### Easy-run heart-rate cap

- **Default:** top of Zone 2 from the user's Coros zones, preferably zones based on lactate threshold HR. These are more accurate than zones from max HR, because max HR formulas can be off by about 10 bpm.
- **Editable:** the user can override the number.
- **Retest reminder:** every 8 weeks, or after a race, prompt a threshold test.
- **Compliance:** an easy run counts as compliant if its average HR is at or under the cap.
- **Which runs are easy:** until the app has its own plan (M3), any run under 60 minutes counts as easy, matching the day types under Food targets. From M3, the plan's own label decides. Confirmed by the owner on 2 Oct 2026.
- **Zone values:** The Coros MCP doesn't return zone values (checked 2 Oct 2026). At setup, the user copies the top of their Zone 2 in bpm from the Coros app; the app uses that number for compliance checks. Planned workouts still target Zone 2 by name, so the watch always uses the live Coros zones.

### Load guard

This applies when a plan is built or edited.

- Weekly running volume rises no more than 10% above the biggest of the previous 3 weeks, so a normal week after a recovery week is not flagged.
- The long run grows by no more than 2 km past the longest run of the previous 3 weeks, and stays at or under 35% of weekly volume (50% when the race is a trail ultra, longer than a marathon).
- Every 4th week is a recovery week at about 75% of the previous week's volume.
- No two long or hard days back to back.
- After a race, 7 days easy before any hard session.
- For a half marathon, the final 2 weeks taper.

### Race goals

A race goal has three fields:

| Field | Required |
| --- | --- |
| Race date | Yes |
| Race distance | Yes |
| Target time | No, optional |

With no target time, the plan builds toward completing the distance, and the app shows the Coros race prediction for reference.

### Food targets by day type

| Day type | How it's set | Carbs (owner at 78.6 kg) | Protein (owner) |
| --- | --- | --- | --- |
| Rest | No session planned or done | 3 g/kg (about 236 g) | 1.6 g/kg (about 126 g) |
| Easy | Easy run, strength, or under 60 min | 5 g/kg (about 393 g) | 1.6 g/kg (about 126 g) |
| Hard or long | Intervals, tempo, or 90+ min | 7 g/kg (about 550 g) | 1.6 g/kg (about 126 g) |

- **Calories:** resting energy from the Mifflin-St Jeor equation, plus that day's active calories from Coros. For the owner, resting energy is about 1,730 kcal a day. (Men: 10 × kg + 6.25 × cm − 5 × age + 5. Women: same, − 161.)
- **Weight goal:** a weight-loss goal subtracts up to 500 kcal on rest and easy days, set from the target weight and date; carbs shrink to fit, never below 3 g/kg. No deficit on hard or long days or around a race (see Decisions for F4). The 500 cap is a proposed default with no source yet.
- **Fat:** the calories left over, never below 20% of the day's calories.
- **Where the numbers come from:** the 2016 joint position of the American College of Sports Medicine, the Academy of Nutrition and Dietetics and Dietitians of Canada: carbs 3 to 5 g/kg on light days, 5 to 7 g/kg at about 1 hour a day, 6 to 10 g/kg at 1 to 3 hours a day; protein 1.2 to 2.0 g/kg; fat not kept below 20% of energy. Each default sits inside those ranges ([position paper](https://www.dietitians.ca/DietitiansOfCanada/media/Documents/Resources/noap-position-paper.pdf?ext=.pdf), [Mifflin-St Jeor](https://pubmed.ncbi.nlm.nih.gov/2305711/)).
- **Always an estimate:** every target carries an Estimate label on screen and can be edited.

## Screens and key flows

This section fixes structure. The look is set out under Visual design, below.

**Navigation:** four bottom tabs, plus Settings and the widget.

| Screen | What it shows | Main actions |
| --- | --- | --- |
| Home (was Today) | Goals first, each with a status (On track, Watch, Off track) and its reasons; this week so far; insights that apply; then today's verdict as one line (signals behind a tap), today's workout and swap advice, and yesterday's easy run only when it was over the cap | Open the signals; Check now |
| Plan | Goals, the current block by week, upcoming workouts | Set goal; adopt a Coros plan or build one; push to watch; move a session |
| Week | The weekly review, with history back to the 12-week baseline; Places card with a map preview (M5) | Pick a past week; open a metric's trend; open the run map |
| Run map (M5) | Every outdoor GPS activity on a dark map: clustered pins zoomed out, route lines zoomed in | India or World view; filter by activity type; tap a route for its details |
| Log | Today's meals and macros against target, weight trend | Add a meal; log a saved meal; enter weight |
| Settings | Coros connection, HR cap, wake time, goals, thresholds, home privacy zone (M5), backup, error log | Reconnect Coros; edit rules; set home zone; back up or restore; export error log |
| Widget | Verdict, the main reason, today's workout | Opens Today; Check now |

**Key flows**

1. **First run:** connect Coros (OAuth in the browser), import the last 12 weeks, enter the HR cap (top of Coros Zone 2 in bpm), set wake time, set the first goal, turn on Drive backup.
2. **Morning:** the watch syncs, the app sees new sleep data, a notification and the widget show the verdict, the user opens Today and accepts or swaps the workout.
3. **Plan:** set goal and date, pick a Coros plan or build one, the load guard checks it, the user reviews the weeks and pushes them to the watch.
4. **Log a meal:** tap +, pick a saved meal or enter a new one, totals update against the day-type target.
5. **Sunday:** a notification arrives, the Week screen shows the summary and the one thing to change.

### Visual design

The owner shared five reference mockups on 2 Oct 2026, in `appdesignreference/ref_1.webp` to `ref_5.webp` in this folder. **Look at them before building any screen.** They show a dark nutrition tracker: true-black screens, near-black cards with large rounded corners, one lime-green accent, big bold numbers and quiet grey labels. Each screen leads with one hero element.

**Principle:** the references set the look and feel only. What the app shows and does comes from this PRD, so each reference element is kept, adapted or dropped based on what makes sense for Training Companion.

**Theme:** dark only in v1.

**Colours** (sampled from the references)

| Token | Hex | Use in Training Companion |
| --- | --- | --- |
| Background | #000000 | All screens |
| Surface | about #0C0C0C to #141414 | Cards, tiles, bottom bar (approximate) |
| Text | #FFFFFF | Titles and numbers |
| Text secondary | #A9AAA3 | Labels and units |
| Accent, Go | #97EB78 (buttons #A1F882) | Primary buttons, Go as planned, on target |
| Amber, Go easy | #E5A438 | Go easy, over target, carbs |
| Coral, Rest | #EE7469 | Rest, missed, protein |
| Blue | #6496DE | Fat |
| Sky | #35AAE7 | Toggles, sleep |

**Type:** Inter Tight, free on Google Fonts (OFL). SemiBold (600) with slightly tight letter spacing (about -2%) for titles and big numbers; Regular and Medium for labels; small uppercase letter-spaced labels for dates and section headers. Bundle the font files in the app (don't fetch them at runtime) so it works offline. Picked after rendering six free fonts beside the reference headlines; Inter Tight matched the compact, tight-set titles most closely.

**Reference elements and where they go**

| In the references | In Training Companion |
| --- | --- |
| Calorie ring with Eaten, Burned and Fibre rows (ref_3, ref_4 Home) | Today: verdict ring coloured Go, Go easy or Rest, with HRV, resting HR, sleep and load rows beside it |
| Protein, carbs and fat tiles with progress bars | Today: signal tiles, value against normal range. Log: macro tiles against the day-type target |
| Scan food, Search and Voice log tiles | Today: Check now, Log weight, Swap workout |
| Meal list with macro chips (14P 52C 9F) and serving steppers | Log screen |
| Food search with filter chips (ref_3) | Food search with chips for All, IFCT, Packaged and My foods |
| Food detail with macro bars (ref_5) | Food detail, without the photo, health score or vitamins |
| Progress: green and amber bar chart, three-stat row, weight line with gradient fill, goals-hit bars (ref_1, ref_2) | Week screen: daily load or km bars, a compliance, strength and best-day row, weight trend, goal progress |
| Week, Month and Year segmented control | Week screen range; Yesterday and Today switcher on Log |
| Floating pill bottom bar with a raised centre button | Today, Plan, a + button to log a meal or weight, Week, Log. Settings opens from a top-right avatar |
| Toggle rows | Settings: notifications and backup |
| Dashed "Nothing logged yet" card | Empty states |

**Left out:** food photos and camera or voice logging (no photo logging in v1), coach prompts such as "Ask the coach" (no AI), health and nutrition scores, vitamins, and hydration.

**Android:** the references are iPhone mockups. The app uses Android's status and navigation bars and Material 3 components restyled to these tokens. The home screen widget uses the same look: black, the verdict ring, and one line giving the main reason.
## Technical approach

The app is built in **Flutter** for Android only. The owner builds it with Claude. There is no server: all logic and data stay on the phone, and backup goes to the owner's own Google Drive at no cost.

**Architecture (everything runs on the phone; only Coros and the user's Drive sit outside)**

- **Screens and widget** (Today, Plan, Week, Log, Settings, home screen widget) read from the rules engine and the local database.
- **Rules engine:** verdict, load guard, targets, weekly review. Reads only from the local database, so every screen works offline.
- **Local database (SQLite):** Coros history, meals, weight, plans, goals.
- **Sync worker:** polls the COROS MCP for new data and pushes planned workouts. Plans are saved to the database first.
- **Backup job:** copies the database to the user's Google Drive (hidden app folder, free).
- **Outside the phone:** COROS MCP (mcp.coros.com, OAuth 2.0, polled), which syncs with the Coros watch through the Coros app; and Google Drive.

| Part | Choice | Why |
| --- | --- | --- |
| Framework | Flutter (Dart) | Fast to build with; solid charts and background-task support |
| Coros connection | MCP client over HTTP (JSON-RPC), OAuth 2.0 with PKCE | Coros's documented route for single-user apps |
| Token storage | Android Keystore via secure storage | Tokens never sit in plain files |
| Local database | SQLite | History, meals, weight, plans and goals on the phone |
| Background sync | Android WorkManager, every 15 min in the morning window plus a daily catch-up | No Coros webhooks, so the app polls |
| Widget | Native home screen widget fed by the Flutter app | Flutter can't draw widgets by itself; a small native layer per platform |
| Notifications | Local notifications | No server needed |
| Backup | Google Drive app data folder, via Google sign-in | Free, private to the user, survives a phone change |
| Rules | Pure Dart module with unit tests, using the 12-week baseline as test data | Rules can be checked against real history before shipping |
| Error log | Local, viewable and exportable in Settings | Catches silent failures in the background sync without sending data anywhere |
| Run map (M5) | `flutter_map` with CARTO Dark Matter tiles (free personal key, no account), or OpenStreetMap tiles darkened on the phone without a key; attribution shown | Free for one personal, non-commercial user under both providers' terms |
| Route data (M5) | GPS tracks from FIT files, simplified and stored in SQLite | Draws routes offline; a daily download budget keeps the 50 FIT files a day cap clear for the morning sync |

**Risks**

- **Android background limits.** Since Android 15, apps that aren't in front have no network unless they run a scheduled job or a foreground service (M0 found this on the owner's phone). Sign-in therefore finishes once the app is back in front, and the morning sync runs as WorkManager jobs with a network constraint.
- **Coros MCP is new and changing.** Tool names and outputs may change. Replies are free text with no version and no structured alternative, so a wording change can break parsing without any error from Coros. Mitigations: the Coros layer is kept separate so changes stay in one place; each tool has a strict parser tested against real saved replies, including no-data replies; a parse failure goes to the error log and shows a banner on Today; and raw replies are stored next to parsed values so a fixed parser can re-read history without fetching again.

### Coros sign-in without a server

The owner ruled out a hosted sign-in relay on 2 Oct 2026, so sign-in happens entirely on the phone. Coros's own official CLI (npm `coros-mcp` 0.1.1) shows this works. It:

1. Registers itself at Coros's `/connect/register` endpoint as a public client with no secret (`token_endpoint_auth_method: none`), with `grant_types: ["authorization_code", "refresh_token"]`, `response_types: ["code"]` and scope `openid offline_access mcp.tools`. Coros returns the same client ID for a repeated `client_name` (found in M0), so every install registering as "Training Companion" would share one client and its redirect list. The app registers once on first run under a unique name, for example "Training Companion · a1b2c3d4", stores the client ID in secure storage with the tokens, and re-registers only if Coros rejects it.
2. Opens `/oauth2/authorize` with PKCE (S256), `resource` set to the MCP URL, and a `state` value.
3. Swaps the returned code at `/oauth2/token` for access and refresh tokens, then refreshes them later, still with no secret.

Coros's [server metadata](https://mcp.coros.com/.well-known/oauth-authorization-server) confirms a registration endpoint, PKCE S256, refresh tokens, and the scopes `openid`, `mcp.tools` and `offline_access`. The issuer is regional (for example `https://mcpus.coros.com`); read it from the metadata rather than hard-coding it. The metadata lists `none` among the token endpoint auth methods, so secret-less clients are supported.

The spike tries the on-device paths in this order. M0 tested the Coros side from a laptop on 2 Oct 2026:

| Path | How it works on Android | Evidence | Risk |
| --- | --- | --- | --- |
| 1. Local (loopback) redirect | The app listens on 127.0.0.1 while the user signs in, and Coros redirects there | Coros's CLI uses `http://127.0.0.1:43123/callback`. **M0: full sign-in, refresh and data reads passed with this redirect** | Port clashes are solved: M0 showed Coros accepts any loopback port, so the app takes a free one at sign-in. **M0 on the owner's phone: the listener caught the code in the background; sign-in, reads, a workout write and the widget all worked** |
| 2. https App Link redirect | Sign-in opens in a Chrome Custom Tab; Coros redirects to an https link the app owns, and Android hands it to the app | **M0: Coros accepts https redirects at registration, but rejects custom schemes** such as `com.trainingcompanion.app:/oauth/callback` ("Remote redirect_uri must use https") | Needs a domain serving a static `/.well-known/assetlinks.json`. That file is not a relay: no tokens or codes pass through it |
| 3. Login-ticket flow | The app opens a Coros login link, polls until the user approves, then finishes sign-in itself, with no redirect | Coros's CLI uses this for its device login (`/api/v1/cli/login-sessions`, then `/claim` with an `X-Poll-Token`, then authorize with the login ticket and read the code from the redirect's Location header) | Uses endpoints Coros hasn't documented publicly, which may change |

Coros's metadata also advertises a device authorization flow (RFC 8628), but M0 found it closed to self-registered apps: registration strips the `device_code` grant and the endpoint returns 401.

If all three fail, the next step is asking Coros (api@coros.com) how a single-user mobile app should register. A hosted relay stays off the table.

### Development setup

The app is built on the owner's own laptop, because Android builds and testing need local tools and a phone.

- **Claude Code**, in the Claude desktop app's Code tab, the terminal, or VS Code. Cursor isn't required.
- **Flutter SDK** and **Android Studio**, which installs the Android SDK.
- **The owner's Android phone** with USB debugging on, to test the widget, notifications and morning sync on a real device.

## Privacy and data handling

Health and training data stays on the user's phone and in their own Google Drive. The app runs no server and collects nothing.

- **No accounts of our own.** The owner signs in with Coros, and with Google for backup.
- **Coros tokens** live in Android Keystore and never leave it: they're excluded from the Drive backup and the CSV export. M0 found that a client with no secret can't revoke its tokens (Coros returns 401 and the tokens keep working), so disconnect and delete-everything delete the tokens from the phone, and tell the user how to remove the app's access on the Coros side. A copied token would stay valid until it expires, which is why tokens must never leave Keystore.
- **Location.** Coros activity records include GPS start coordinates, which for runs from home effectively give the home address. The app keeps them, and the GPS routes, for the run map (F5), and like all other data they stay on the phone and in the user's own Drive backup. The CSV export includes them, and says so. The home privacy zone hides route sections and pins near home on the map; it doesn't change what's stored or exported.
- **Backup** goes to the Drive app data folder, which only this app can see. Restore works on a new phone.
- **No analytics, ads or crash-reporting SDKs.** A local error log only, viewable and exportable in Settings; it's enough for a single user who can share logs directly.
- **Export and delete.** Settings offers a full data export (CSV) and a delete-everything option that also clears the Drive backup.

## Success metrics

The app succeeds if the owner keeps using it and the training problems in the baseline improve over a full block. Targets are **confirmed by the owner**.

| Metric | Baseline (6 Jul to 30 Sep) | Target |
| --- | --- | --- |
| Days the morning check is viewed (widget or app) | Not tracked | 5+ of 7 days, for 4 straight weeks |
| Easy runs at or under the HR cap | Set once the cap is confirmed | 80%+ |
| Strength sessions a week | 1.2 average (15 in 13 weeks) | 2 a week, in 3 of every 4 weeks |
| Days in Coros Excessive load | 4 of the last 31 days | 0 outside a race week |
| Weekly volume change | Swung 5 to 34 km | Within the load guard limits every week |
| Pace at a fixed easy HR on the home loop | about 8:15 to 7:52 per km since July | Faster over 8 to 12 weeks |
| Days with weight logged | None | 5+ of 7 days |
| Days with meals logged | None | 5+ of 7 days |
| Nights under 6 hours of sleep | 16 of 72 nights with data | Tracked only; no target in v1 |

**Keep-using test:** the owner uses the app for 4+ weeks and wants to keep using it, and the morning check gives a correct verdict on the owner's own judgement on at least 4 of 5 days.

## Milestones

The Coros sign-in spike comes first, because everything depends on it. Each milestone starts only after the one before passes its gate.

1. **M0 · Technical spike:** Coros sign-in from a phone app, read a day of data, write one workout, prove the widget.
   *Gate: Coros accepts the app's sign-in and returns data.*
2. **M1 · Morning check:** sync worker, rules engine, Today screen, widget, notifications, Drive backup, settings, local error log.
   *Gate: the verdict feels right on 4 of 5 days over 2 weeks.*
3. **M2 · Weekly review:** Week screen, Sunday summary, 12-week baseline as history.
4. **M3 · Goals and plan guard:** goals, following the owner's Coros plan, load guard, plan-based easy-run labels, swap advice, goal progress, retest reminder. *(Scope changed by the owner on 5 Oct 2026; see Decisions for F2.)*
4a. **Planner (after Malnad, 27 Nov 2026):** rule-built plans pushed to the watch as MCP plans, with swaps and missed-session adjustments applied on the watch.
5. **M4 · Food and body log:** meals, macros, saved meals, morning weight, day-type targets.
   *Gate: the owner uses it 4+ weeks and wants to keep going.*
6. **M5 · Run map:** Places card and full-screen map, start pins for all history, route backfill within the FIT budget, home privacy zone.

Milestones are built in order, one at a time. The owner decides after each one whether to start the next. The owner confirmed the order of M2 to M4.

## Open questions

- [x] Visual design: dark only, Inter Tight, and a + centre button for logging a meal or weight. References guide look and feel only
- [x] Crash reporting: not needed. The owner is the only user (7 Oct 2026); the local error log covers it.
- [x] Spike: confirm Coros accepts the Android app's sign-in, trying the three on-device paths in order. No hosted relay. *Passed on 2 Oct 2026 with path 1 (loopback) on the owner's phone; paths 2 and 3 not needed.*
- [x] Spike: does Coros accept a loopback sign-in on a port other than the registered one? Yes (2 Oct 2026).
- [x] Spike: can a public client revoke its tokens with no secret? No (2 Oct 2026); see Privacy.
- [ ] Does the Coros app let a user see and remove authorised apps? Owner to check.
- [x] Run map: does getActivityDetail return GPS track points? No; FIT files are the only route source.
- [x] Run map, before M5: download one FIT file and confirm it carries the GPS track. *Yes, 7 Oct 2026: 2,093 points a second for a 35-minute run.*
- [x] Run map tile terms: personal, non-commercial use by one person fits CARTO's free key and OpenStreetMap's tile policy (7 Oct 2026).
- [x] Food data terms: IFCT, USDA and Open Food Facts data are used privately by the owner and not redistributed (7 Oct 2026).
- [ ] Drive backup: publish the Google OAuth consent screen (Audience, Publish app) so Google stops expiring the sign-in every 7 days. Only the non-sensitive `drive.appdata` scope is used, so no review is needed. *Owner decision, 2 Oct 2026: stays in Testing until all updates are done; reconnecting backup every 7 days is acceptable until then.* Publishing the consent screen only changes its status in Google Cloud; it doesn't make the app available to anyone else, so it fits the sole-user decision.

All other decisions are recorded in the live PRD's decisions table.

## Sources

- [COROS MCP on GitHub](https://github.com/coroslab/COROS-MCP)
- [Build on COROS MCP](https://support.coros.com/hc/en-us/articles/53181619102996)
- [Partner API Access](https://support.coros.com/hc/en-us/articles/53181766856724-Partner-API-Access)
- [COROS MCP server metadata](https://mcp.coros.com/.well-known/oauth-authorization-server)
- [coros-mcp on npm](https://www.npmjs.com/package/coros-mcp)
- [ACSM / Dietitians of Canada position paper (2016)](https://www.dietitians.ca/DietitiansOfCanada/media/Documents/Resources/noap-position-paper.pdf?ext=.pdf)
- [Mifflin-St Jeor equation](https://pubmed.ncbi.nlm.nih.gov/2305711/)
- [IFCT 2017 dataset](https://zenodo.org/records/7088653)
