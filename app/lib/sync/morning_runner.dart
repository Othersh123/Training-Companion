import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../backup/drive_backup.dart';
import '../coros/coros_auth.dart';
import '../coros/coros_mcp.dart';
import '../data/app_database.dart';
import '../notify/notifier.dart';
import '../rules/morning_check.dart';
import '../rules/weekly_review.dart';
import '../widget/home_widget_updater.dart';
import 'coros_sync.dart';

const morningSyncTask = 'tc-morning-sync';

/// Entry point for WorkManager. Runs in its own isolate, so it opens everything itself.
/// WorkManager jobs with a network constraint get network access in the background (L20).
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    DartPluginRegistrant.ensureInitialized();
    final sw = Stopwatch()..start();
    try {
      await MorningRunner.runScheduled(DateTime.now()).timeout(const Duration(minutes: 8));
      if (sw.elapsed > const Duration(minutes: 1)) await _logBackground('background run took ${sw.elapsed.inSeconds} s');
    } catch (e) {
      // Into the app's error log, not just the console: on 13 Oct 2026 a stuck background job
      // left no trace at all (L55). WorkManager stops a job at 10 minutes; this stops it at 8.
      debugPrint('TC_SYNC background run failed: $e');
      await _logBackground('background run failed after ${sw.elapsed.inSeconds} s: $e');
    }
    return true; // never ask WorkManager to retry; the next 15-minute run is the retry
  });
}

Future<void> _logBackground(String message) async {
  try {
    await (await AppDatabase.open()).logError('background', message);
  } catch (_) {
    // Nowhere left to report it.
  }
}

/// Registers the periodic job. It wakes every 15 minutes and only does work inside the
/// morning window (wake time + 2 hours), plus one catch-up run if the window was missed.
Future<void> scheduleMorningSync() async {
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    morningSyncTask,
    morningSyncTask,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}

/// Diagnostics: runs the same background job once, now, in the background isolate.
Future<void> runBackgroundJobOnce() async {
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerOneOffTask(
    'tc-diagnostic-${DateTime.now().millisecondsSinceEpoch}',
    morningSyncTask,
    constraints: Constraints(networkType: NetworkType.connected),
  );
}

class MorningRunner {
  static const window = Duration(hours: 2);

  /// Called by the background job. Decides whether this run should poll Coros.
  static Future<void> runScheduled(DateTime now) async {
    // The app's own connection, shared (L55): sqflite runs every database on one native
    // thread, so a second connection deadlocked with the app's whenever their work overlapped
    // (endless loading, a background job stuck "running"). Not closed here: closing a shared
    // connection would close the app's too (L26). It closes when the process ends.
    final db = await AppDatabase.open();
    await _morning(db, now);
    await placesIfDue(db, now);
  }

  /// Run map (M5): the whole activity list once, then up to 5 routes a run inside the daily
  /// FIT budget, so history fills in over a few days without anyone waiting for it.
  static Future<void> placesIfDue(AppDatabase db, DateTime now, {String owner = 'background', int maxRoutes = 5}) async {
    if (await db.setting(SettingKeys.onboarded) != 'true') return;
    final auth = CorosAuth((m) => debugPrint('TC_AUTH $m'));
    if (await auth.loadTokens() == null) return;
    if (!await db.tryLease(owner)) return;
    try {
      final sync = CorosSync(db, McpToolCaller(CorosMcp(auth)));
      if (await db.setting(SettingKeys.allActivitiesImportedAt) == null) await sync.importAllActivities(now);
      await sync.syncRoutes(max: maxRoutes, now: now);
    } on CorosUnreachable {
      // Logged by the sync; the next run retries.
    } finally {
      await db.releaseLease(owner);
    }
  }

  /// The morning check, when it's due (and the Sunday summary).
  static Future<void> _morning(AppDatabase db, DateTime now) async {
    final wake = parseWakeTime(await db.setting(SettingKeys.wakeTime));
    if (wake == null) return; // onboarding not finished
    await weeklySummaryIfDue(db, now);
    final start = DateTime(now.year, now.month, now.day, wake.$1, wake.$2);
    if (now.isBefore(start)) return;

    final existing = await db.checkOn(corosDateOf(now));
    if (existing != null && existing.isFinal) return;

    try {
      await runNow(db, now, windowClosed: !now.isBefore(start.add(window)));
    } on CorosUnreachable {
      // Already handled (notified when the window closes); routes may still try below.
    }
  }

  /// Sunday from 19:00 (editable): sync the week, review it, notify once per week (PRD F3).
  static Future<void> weeklySummaryIfDue(AppDatabase db, DateTime now) async {
    if (now.weekday != DateTime.sunday) return;
    final at = parseWakeTime(await db.setting(SettingKeys.weeklyReviewTime)) ?? (19, 0);
    if (now.isBefore(DateTime(now.year, now.month, now.day, at.$1, at.$2))) return;
    final monday = mondayOf(now);
    if (await db.setting(SettingKeys.weeklyNotifiedFor) == corosDateOf(monday)) return;

    final auth = CorosAuth((m) => debugPrint('TC_AUTH $m'));
    if (await auth.loadTokens() == null) return;
    final sync = CorosSync(db, McpToolCaller(CorosMcp(auth)));
    try {
      await sync.syncWeek(monday, now);
      await sync.syncBlock(now); // pick up plan changes made in the Coros app
    } on CorosUnreachable {
      return; // the next 15-minute run retries
    }
    // By Sunday evening the week's sessions are done: review it as complete.
    final r = await sync.weekReviewFromDatabase(monday, asOf: monday.add(const Duration(days: 7)));
    if ((await db.setting(SettingKeys.notificationsOn)) != 'false') {
      final easy = r.easyRuns == 0 ? '' : ' · easy runs ${r.easyUnderCap}/${r.easyRuns} under cap';
      await Notifier.show(id: Notifier.weeklyId, title: 'Your week: ${r.kmRun.toStringAsFixed(1)} km$easy', body: r.oneThing.text);
    }
    await db.setSetting(SettingKeys.weeklyNotifiedFor, corosDateOf(monday));
  }

  /// One poll: used by the background job and by Check now. Only one runs at a time (L46):
  /// Check now during a background run waits for it and then shows its result; a
  /// background run while Check now is going simply skips.
  static Future<SyncResult?> runNow(AppDatabase db, DateTime now, {required bool windowClosed, bool fromUser = false}) async {
    final owner = fromUser ? 'app' : 'background';
    if (!await db.tryLease(owner)) {
      if (!fromUser) return null;
      for (var i = 0; i < 90 && await db.leaseHeldByOther(owner); i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      if (!await db.tryLease(owner)) return null;
      // The other run may already have stored today's final verdict: don't fetch it twice.
      final done = await db.checkOn(corosDateOf(now));
      if (done != null && done.isFinal && done.computedAt.isAfter(now.subtract(const Duration(minutes: 5)))) {
        await db.releaseLease(owner);
        return null;
      }
    }
    try {
      return await _poll(db, now, windowClosed: windowClosed, fromUser: fromUser);
    } finally {
      await db.releaseLease(owner);
    }
  }

  static Future<SyncResult?> _poll(AppDatabase db, DateTime now, {required bool windowClosed, required bool fromUser}) async {
    final auth = CorosAuth((m) => debugPrint('TC_AUTH $m'));
    if (await auth.loadTokens() == null) return null;
    final sync = CorosSync(db, McpToolCaller(CorosMcp(auth)));
    final notificationsOn = (await db.setting(SettingKeys.notificationsOn)) != 'false';

    SyncResult result;
    try {
      result = await sync.runMorningCheck(now, windowClosed: windowClosed);
    } on CorosUnreachable {
      final today = await db.checkOn(corosDateOf(now));
      if (windowClosed && !fromUser && notificationsOn && (today == null || !today.notified)) {
        await Notifier.show(title: 'Couldn\'t reach Coros', body: 'The morning check will retry. Tap to check now.');
        if (today != null) await db.markNotified(today.check.date);
      }
      rethrow;
    }

    final workout = (await db.scheduleOn(result.check.date)).firstOrNull;
    await HomeWidgetUpdater.show(result.check, workoutName: workout?.name);

    final stored = await db.checkOn(result.check.date);
    // A final verdict the user already saw in the app needs no notification.
    if (result.isFinal && fromUser && stored != null && !stored.notified) {
      await db.markNotified(result.check.date);
      return result;
    }
    if (result.isFinal && !fromUser && notificationsOn && stored != null && !stored.notified) {
      if (result.lastNightArrived || result.check.verdict != Verdict.notEnoughData) {
        await Notifier.show(title: verdictLabel(result.check.verdict), body: result.check.reason);
      } else {
        await Notifier.show(title: 'No sleep data from Coros yet', body: '${result.check.reason}. Sync your watch, then tap Check now.');
      }
      await db.markNotified(result.check.date);
    }
    if (result.isFinal && !fromUser) await DriveBackup.dailyIfDue(db);
    return result;
  }
}

/// "06:30" -> (6, 30)
(int, int)? parseWakeTime(String? hhmm) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hhmm ?? '');
  if (m == null) return null;
  return (int.parse(m.group(1)!), int.parse(m.group(2)!));
}

String corosDateOf(DateTime now) =>
    '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
