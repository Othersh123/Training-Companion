# How Training Companion works

A plain-language tour of the setup: where the data lives, why there's no backend, and what happens when you tap **Check now**.

## Where the data lives

**On the phone, in one file.** The app keeps everything in a single SQLite database inside its private storage on the phone. Think of it as one notebook with many pages, a few megabytes in size:

- **What Coros sent:** sleep, HRV, resting heart rate, training load, activities, the training plan, and GPS routes for the map.
- **What the user entered:** meals, recipes, saved meals, weight, goals and settings.
- **What the app worked out:** each morning's verdict, and an error log.

Android keeps the file private to the app. A copy goes to the user's own Google Drive once a day, into a hidden app folder only this app can see. That's the backup for a lost or new phone.

## Is there a backend?

**No.** There is no server. The phone talks directly to the services it needs:

| Service | What for |
| --- | --- |
| **COROS MCP** (mcp.coros.com) | Watch data and the training plan, with the user's own Coros sign-in, stored securely on the phone |
| **Google Drive** | The daily backup |
| **Map tiles** (CARTO or OpenStreetMap) | The run map's background |
| **Open Food Facts** | Searching packaged foods |

All the thinking happens on the phone: the verdict, the weekly review, food targets, goal status, and the load guard over the plan. The rules are written into the app, so almost everything works offline. Only fetching new Coros data needs a connection.

## What happens when you tap Check now

1. **One check at a time.** If the automatic morning check is already running in the background, Check now waits for it and shows its result instead of asking Coros twice.
2. **Sign-in.** The app confirms the Coros sign-in is valid, and quietly renews it if it's about to expire.
3. **It asks Coros for the morning's data, one question at a time:**
   - Last night's HRV
   - Resting heart rate
   - Last night's sleep
   - Training load
   - Recent activities
   - Today's planned workout
   - Today's active calories

   Coros answers each question in prose, written for AI assistants, not as structured data. The app reads each answer with a strict parser. If Coros changes its wording and an answer can't be understood, that signal is marked as an error instead of being guessed.
4. **It saves everything** to the database, including Coros's original replies, so a misread can be re-parsed later without asking Coros again.
5. **It makes the call** from four signals (HRV, resting heart rate, sleep and training load):

   | Signals flagged | Verdict |
   | --- | --- |
   | None | Go as planned |
   | One | Go easy (keep the session, cap the effort) |
   | Two or more | Rest |
6. **It updates the screens and the home-screen widget.**

The whole check takes a few seconds.

## Without tapping anything

Every 15 minutes Android briefly wakes the app in the background, even when it's closed:

- **Mornings:** from the user's wake time, it runs the same check until last night's sleep and HRV have synced from the watch, then sends the verdict as a notification.
- **Sunday evenings:** it reviews the week and sends a one-line summary with the one thing to change.
- **Through the day:** it downloads a few more GPS routes for the map, within Coros's limit of 50 FIT files in any 24 hours.
- **Once a day:** it backs up to Drive.

## One lesson from building it

The background check and the screens share one database. Early on they used separate connections, and because the database library runs all work on a single thread, the two could jam each other: endless loading on screen, and a background job that never finished. The fix was one shared connection. Small architecture choices like this only show up on a real device, used daily. That's why every milestone here was tested on the phone, not just in code. The full log of 55 such findings is in [learnings.md](../learnings.md).
