import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../coros/coros_mcp.dart';
import '../coros/parsers.dart';
import '../data/app_database.dart';
import '../data/food_store.dart';
import '../data/map_store.dart';
import '../map/fit_route.dart';
import '../rules/morning_check.dart';
import '../data/goal.dart';
import '../rules/load_guard.dart';
import '../rules/planned_workout.dart';
import '../rules/weekly_review.dart';

/// Thrown when Coros can't be reached at all; the last stored check stays in place.
class CorosUnreachable implements Exception {
  CorosUnreachable(this.cause);
  final Object cause;
  @override
  String toString() => 'Could not reach Coros: $cause';
}

/// Talks to the "call a Coros tool" part of the MCP client; an interface so tests can use fixtures.
abstract class ToolCaller {
  Future<String> callTool(String name, Map<String, dynamic> args);
}

class McpToolCaller implements ToolCaller {
  McpToolCaller(this.mcp);
  final CorosMcp mcp;
  @override
  Future<String> callTool(String name, Map<String, dynamic> args) => mcp.callTool(name, args);
}

class SyncResult {
  SyncResult(this.check, {required this.isFinal, required this.lastNightArrived});
  final MorningCheck check;
  final bool isFinal;

  /// Last night's sleep and HRV are both in.
  final bool lastNightArrived;
}

/// Polls Coros, stores raw and parsed replies, and runs the morning check from the database.
class CorosSync {
  CorosSync(this.db, this.coros, {Future<Uint8List> Function(Uri)? download}) : _download = download ?? _httpDownload;

  /// Fetches a FIT file from the URL Coros gives (tests pass a fake).
  final Future<Uint8List> Function(Uri) _download;

  static Future<Uint8List> _httpDownload(Uri url) async {
    final res = await http.get(url).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw HttpException('FIT download returned ${res.statusCode}');
    return res.bodyBytes;
  }

  final AppDatabase db;
  final ToolCaller coros;

  /// Fetches one tool, saves the raw reply, parses and stores it.
  /// Returns null on success, or the format error message (also logged).
  Future<String?> _fetch<T>(String tool, Map<String, dynamic> args, T Function(String) parse, Future<void> Function(T) store) async {
    final String text;
    try {
      text = await coros.callTool(tool, args);
    } catch (e) {
      await db.logError('sync', '$tool: $e');
      throw CorosUnreachable(e);
    }
    try {
      final parsed = parse(text);
      await db.saveRaw(tool, args, text);
      await store(parsed);
      return null;
    } on CorosFormatException catch (e) {
      await db.saveRaw(tool, args, text, parseError: e.message);
      await db.logError('parser', e.toString());
      return e.toString();
    }
  }

  /// One morning poll: fetch what the verdict needs, compute it, and store it.
  Future<SyncResult> runMorningCheck(DateTime now, {required bool windowClosed}) async {
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final todayArg = corosArgDate(today);

    final errors = <String, String?>{
      'hrv': await _fetch('querySleepHrv', {'startDate': todayArg, 'endDate': todayArg, 'days': 1}, parseSleepHrv, db.saveHrv),
      'rhr': await _fetch('queryRestingHeartRate', {'days': 31}, parseRestingHr, db.saveRestingHr),
      'sleep': await _fetch('querySleepOverview', {'startDate': todayArg, 'endDate': todayArg}, parseSleepOverview, db.saveSleep),
      'load': await _fetch('queryTrainingLoadAssessment', {'days': 1}, parseTrainingLoad, db.saveLoad),
      'activities': await _fetch('querySportRecords', _recordsArgs(yesterday, today), parseSportRecords, db.saveActivities),
    };
    await syncSchedule(today, today);
    await syncLaps(await db.activitiesBetween(corosDate(yesterday), corosDate(today)));
    // Yesterday's final active calories, for food targets (M4). Never blocks the verdict.
    try {
      await syncDailyHealth(2);
    } on CorosUnreachable {
      // Logged by _fetch; the Log screen refreshes it later.
    }

    final check = await computeFromDatabase(today, formatErrors: errors);
    final hrvIn = check.signals.firstWhere((s) => s.signal == Signal.hrv).hasData;
    final sleepIn = check.signals.firstWhere((s) => s.signal == Signal.sleep).hasData;
    final arrived = hrvIn && sleepIn;
    final isFinal = arrived || windowClosed;
    await db.saveCheck(check, isFinal: isFinal);
    return SyncResult(check, isFinal: isFinal, lastNightArrived: arrived);
  }

  /// Fetches the Coros calendar for [from]..[to], then swaps plan codes (S5724) for the plan's
  /// real workouts (L28). Plan details cover at most 28 days per call. If they can't be read,
  /// the codes stay and the error is logged. Returns the schedule format error, if any.
  Future<String?> syncSchedule(DateTime from, DateTime to) async {
    final error = await _fetch('queryTrainingSchedule', {'startDate': corosArgDate(from), 'endDate': corosArgDate(to)},
        parseTrainingSchedule, (Map<CorosDate, List<ScheduledWorkout>> s) => db.saveSchedule(corosDate(from), corosDate(to), s));
    if (error != null) return error;
    final planIds = (await db.scheduleBetween(corosDate(from), corosDate(to)))
        .values
        .expand((day) => day)
        .map((w) => w.planId)
        .nonNulls
        .toSet();
    for (final planId in planIds) {
      for (var start = from; !start.isAfter(to); start = start.add(const Duration(days: 28))) {
        final end = start.add(const Duration(days: 27)).isAfter(to) ? to : start.add(const Duration(days: 27));
        await _fetch('queryTrainingPlanDetails', {'planId': planId, 'startDay': corosArgDate(start), 'endDay': corosArgDate(end)},
            parsePlanDetails, db.applyPlanDetails);
      }
    }
    return null;
  }

  /// Lap data for runs and strength sessions that don't have it yet: run splits for the
  /// fitness trend, body parts for strength (M2). One call per activity, fetched once.
  Future<void> syncLaps(List<Activity> activities) async {
    final wanted = activities.where((a) => a.isRun || a.sportType == strengthSportType).toList();
    final done = await db.lapsFetched(wanted.map((a) => a.labelId));
    for (final a in wanted.where((a) => !done.contains(a.labelId))) {
      final args = {'labelId': a.labelId, 'sportType': a.sportType};
      if (a.isRun) {
        await _fetch('queryActivityLapData', args, parseRunSplits, (List<Split> s) => db.saveSplits(a.labelId, s));
      } else {
        await _fetch('queryActivityLapData', args, parseStrengthLaps, (StrengthSummary s) => db.saveStrength(a.labelId, s));
      }
    }
  }

  /// Everything the weekly review needs for the Monday-to-Sunday week starting [monday].
  Future<void> syncWeek(DateTime monday, DateTime now) async {
    final today = DateTime(now.year, now.month, now.day);
    final sunday = monday.add(const Duration(days: 6));
    final end = sunday.isAfter(today) ? today : sunday;
    final from = corosArgDate(monday), to = corosArgDate(end);
    await _fetch('querySportRecords', _recordsArgs(monday, end, limit: 50), parseSportRecords, db.saveActivities);
    await _fetch('querySleepOverview', {'startDate': from, 'endDate': to}, parseSleepOverview, db.saveSleep);
    await _fetch('queryRestingHeartRate', {'days': 31}, parseRestingHr, db.saveRestingHr);
    // Load can only be fetched for recent days (L27), so keep every day while it's available.
    await _fetch('queryTrainingLoadAssessment', {'days': 31}, parseTrainingLoad, db.saveLoad);
    await syncSchedule(monday, sunday);
    await syncLaps(await db.activitiesBetween(corosDate(monday), corosDate(end)));
  }

  /// The weekly review for the week starting [monday], from stored data only (works offline).
  /// [asOf] decides whether the week counts as complete; the Sunday summary passes the week's end.
  Future<WeekReview> weekReviewFromDatabase(DateTime monday, {DateTime? asOf}) async {
    final sunday = monday.add(const Duration(days: 6));
    final from = corosDate(monday), to = corosDate(sunday);
    final activities = await db.activitiesBetween(corosDate(monday.subtract(const Duration(days: 21))), to);
    final inWeek = activities.where((a) => a.date.compareTo(from) >= 0).map((a) => a.labelId);
    final t = await thresholds();
    final cap = int.tryParse(await db.setting(SettingKeys.easyRunHrCap) ?? '');
    final allRecent = await db.activitiesBetween(corosDate(monday.subtract(const Duration(days: 84))), to);
    return computeWeekReview(
      monday: monday,
      activities: activities,
      schedule: await db.scheduleBetween(from, to),
      splits: await db.splitsFor(inWeek),
      strength: await db.strengthFor(inWeek),
      sleep: await db.sleepBetween(from, to),
      restingHr: await db.restingHrBetween(corosDate(monday.subtract(const Duration(days: 7))), to),
      load: await db.loadBetween(from, to),
      home: homePoint(allRecent),
      s: ReviewSettings(easyRunHrCap: cap, sleepMinMinutes: t.sleepMinMinutes),
      asOf: asOf ?? DateTime.now(),
    );
  }

  /// The calendar from this week to race day (or 8 weeks ahead without a race goal).
  Future<void> syncBlock(DateTime now) async {
    final race = (await db.primaryGoal())?.date;
    final today = DateTime(now.year, now.month, now.day);
    final end = race != null && race.isAfter(today) ? race.add(const Duration(days: 7)) : today.add(const Duration(days: 56));
    await syncSchedule(mondayOf(today), end);
  }

  /// Median pace of the last 4 weeks' easy road runs (under 60 minutes); 7:30/km without any.
  Future<double> easyPace(DateTime today) async {
    final recent = await db.activitiesBetween(corosDate(today.subtract(const Duration(days: 28))), corosDate(today));
    final paces = [
      for (final a in recent)
        if (a.isRoadRun && a.durationSeconds < 3600 && (a.distanceMeters ?? 0) > 2000) a.durationSeconds / (a.distanceMeters! / 1000),
    ]..sort();
    return paces.isEmpty ? 450 : paces[paces.length ~/ 2];
  }

  /// Classified plan workouts for [from]..[to], from stored data.
  Future<Map<CorosDate, List<PlannedWorkout>>> plannedBetween(DateTime from, DateTime to, {double? pace}) async {
    final p = pace ?? await easyPace(from);
    final schedule = await db.scheduleBetween(corosDate(from), corosDate(to));
    return {
      for (final e in schedule.entries) e.key: [for (final w in e.value) classifyWorkout(e.key, w, easyPaceSecondsPerKm: p)],
    };
  }

  /// The load guard over the plan from today to race day, from stored data (works offline).
  Future<GuardResult> guardFromDatabase(DateTime now) async {
    final today = DateTime(now.year, now.month, now.day);
    final race = await db.primaryGoal();
    final raceDate = race?.type == GoalType.race ? race!.date : null;
    final end = raceDate != null && raceDate.isAfter(today) ? raceDate.add(const Duration(days: 7)) : today.add(const Duration(days: 56));
    return runLoadGuard(
      today: today,
      planned: await plannedBetween(today, end),
      runs: await db.activitiesBetween(corosDate(mondayOf(today).subtract(const Duration(days: 21))), corosDate(today)),
      raceDate: raceDate != null && raceDate.isAfter(today) ? raceDate : null,
      s: raceDate == null ? const GuardSettings() : GuardSettings.forRace(trail: race!.terrain == Terrain.trail, distanceMeters: race.distanceMeters),
    );
  }

  /// Computes the check from stored data. A tool whose latest reply couldn't be read
  /// becomes an error signal, never a no-data one.
  Future<MorningCheck> computeFromDatabase(DateTime today, {Map<String, String?> formatErrors = const {}}) async {
    final t = await thresholds();
    final from = corosDate(today.subtract(Duration(days: t.restingHrHistoryDays + 1)));
    final to = corosDate(today);
    final yesterday = corosDate(today.subtract(const Duration(days: 1)));

    Source<T> source<T>(String key, T data) {
      final error = formatErrors[key];
      return error == null ? Source.ok(data) : Source.failed(error);
    }

    final capText = await db.setting(SettingKeys.easyRunHrCap);
    return computeMorningCheck(
      today: today,
      hrv: source('hrv', await db.hrvBetween(to, to)),
      restingHr: source('rhr', await db.restingHrBetween(from, to)),
      sleep: source('sleep', await db.sleepBetween(to, to)),
      load: source('load', await db.loadBetween(to, to)),
      activities: source('activities', await db.activitiesBetween(yesterday, to)),
      easyRunHrCap: capText == null ? null : int.tryParse(capText),
      plannedYesterday: await db.scheduleOn(yesterday),
      t: t,
    );
  }

  Future<Thresholds> thresholds() async {
    Future<int?> intSetting(String key) async => int.tryParse(await db.setting(key) ?? '');
    const d = Thresholds();
    return Thresholds(
      restingHrRiseBpm: await intSetting(SettingKeys.restingHrRise) ?? d.restingHrRiseBpm,
      sleepMinMinutes: await intSetting(SettingKeys.sleepMinMinutes) ?? d.sleepMinMinutes,
      restingHrHistoryDays: await intSetting(SettingKeys.restingHrHistoryDays) ?? d.restingHrHistoryDays,
    );
  }

  /// First-run import of recent history. Large Coros queries fail, so it goes in small chunks
  /// (HRV is capped at 7 days per call; records and sleep by month).
  Future<void> importHistory(DateTime now, {int weeks = 12, void Function(String step, double progress)? onProgress}) async {
    final today = DateTime(now.year, now.month, now.day);
    final start = today.subtract(Duration(days: weeks * 7));
    final steps = <(String, Future<String?> Function())>[];

    for (var from = start; !from.isAfter(today); from = from.add(const Duration(days: 7))) {
      final to = from.add(const Duration(days: 6)).isAfter(today) ? today : from.add(const Duration(days: 6));
      steps.add(('HRV ${corosDate(from)}', () => _fetch('querySleepHrv', {'startDate': corosArgDate(from), 'endDate': corosArgDate(to), 'days': 7}, parseSleepHrv, db.saveHrv)));
    }
    for (var from = start; !from.isAfter(today); from = DateTime(from.year, from.month + 1, from.day)) {
      final next = DateTime(from.year, from.month + 1, from.day).subtract(const Duration(days: 1));
      final to = next.isAfter(today) ? today : next;
      steps.add(('Sleep ${corosDate(from)}', () => _fetch('querySleepOverview', {'startDate': corosArgDate(from), 'endDate': corosArgDate(to)}, parseSleepOverview, db.saveSleep)));
      steps.add(('Activities ${corosDate(from)}', () => _fetch('querySportRecords', _recordsArgs(from, to, limit: 100), parseSportRecords, db.saveActivities)));
    }
    final days = today.difference(start).inDays + 1;
    steps.add(('Resting HR', () => _fetch('queryRestingHeartRate', {'days': days}, parseRestingHr, db.saveRestingHr)));
    steps.add(('Training load', () => _fetch('queryTrainingLoadAssessment', {'days': days}, parseTrainingLoad, db.saveLoad)));
    steps.add(('Active calories', () => syncDailyHealth(35)));

    // The calendar and its plans, for planned-against-done in past weeks.
    steps.add(('Calendar', () => syncSchedule(start, today.add(Duration(days: 7 - today.weekday)))));

    // Lap data: one call per run or strength session, so it's the longest step.
    final total = steps.length + 1;
    for (var i = 0; i < steps.length; i++) {
      onProgress?.call(steps[i].$1, i / total);
      await steps[i].$2();
    }
    onProgress?.call('Splits and strength sets', steps.length / total);
    await syncLaps(await db.activitiesBetween(corosDate(start), corosDate(today)));
    onProgress?.call('Done', 1);
    await db.setSetting(SettingKeys.historyImportedAt, DateTime.now().toIso8601String());
  }

  // ---- run map (M5)

  /// FIT downloads the app allows itself a day, of Coros's 50 (PRD F5: leave room).
  static const dailyFitBudget = 40;

  /// The whole Coros activity list, for start pins (PRD F5). Finds the first year with any
  /// activity (the owner's history starts in 2025), then fetches it a month at a time.
  Future<void> importAllActivities(DateTime now, {void Function(String step)? onStep}) async {
    final today = DateTime(now.year, now.month, now.day);
    var firstYear = now.year;
    for (var y = now.year - 1; y >= 2012; y--) {
      final found = <Activity>[];
      final error = await _fetch('querySportRecords', _recordsArgs(DateTime(y), DateTime(y, 12, 31), limit: 1), parseSportRecords,
          (List<Activity> a) async => found.addAll(a));
      if (error != null || found.isEmpty) break;
      firstYear = y;
    }
    for (var from = DateTime(firstYear); !from.isAfter(today); from = DateTime(from.year, from.month + 1)) {
      final next = DateTime(from.year, from.month + 1).subtract(const Duration(days: 1));
      onStep?.call('${from.year}-${from.month.toString().padLeft(2, '0')}');
      await _fetch('querySportRecords', _recordsArgs(from, next.isAfter(today) ? today : next, limit: 100), parseSportRecords, db.saveActivities);
    }
    await db.setSetting(SettingKeys.allActivitiesImportedAt, DateTime.now().toIso8601String());
  }

  /// Downloads routes for GPS activities that don't have one, newest first, up to [max] and
  /// within the daily budget. Returns how many were stored. Stops at the first Coros
  /// problem (a changed reply, the daily limit); a single bad file is recorded and skipped.
  Future<int> syncRoutes({int max = 10, DateTime? now}) async {
    final at = now ?? DateTime.now();
    // Coros said no recently: don't ask again (and log the same error) until the pause ends.
    final pausedUntil = DateTime.tryParse(await db.setting(SettingKeys.fitPausedUntil) ?? '');
    if (pausedUntil != null && at.isBefore(pausedUntil)) return 0;
    var used = (await db.fitRequestsInLastDay(at)).length;
    var stored = 0;
    for (final a in await db.activitiesNeedingRoutes(at)) {
      if (stored >= max || used >= dailyFitBudget) break;
      final args = {'labelId': a.labelId, 'sportType': a.sportType};
      Uri? url;
      final String? error;
      try {
        error = await _fetch('queryActivityFitFileDownloadUrls', args, parseFitUrl, (Uri u) async => url = u);
      } on CorosUnreachable catch (e) {
        // "You have reached the daily limit of 50 activity FIT files" (8 Oct 2026, L53): pause
        // until the oldest link of the last 24 hours ages out, or 4 hours if none are ours.
        if ('${e.cause}'.contains('daily limit')) {
          final recent = await db.fitRequestsInLastDay(at);
          final until = recent.isEmpty ? at.add(const Duration(hours: 4)) : recent.first.toLocal().add(const Duration(hours: 24, minutes: 5));
          await db.setSetting(SettingKeys.fitPausedUntil, until.toIso8601String());
          return stored;
        }
        rethrow;
      }
      used++;
      if (error != null || url == null) break;
      try {
        final track = readFitTrack(await _download(url!));
        await db.saveRoute(a.labelId, simplifyRoute(track));
        stored++;
      } catch (e) {
        await db.saveRouteError(a.labelId, '$e');
        await db.logError('routes', '${a.date} ${a.name}: $e');
      }
    }
    return stored;
  }

  /// Active calories for the last [days] days (queryDailyHealthData only takes a day count;
  /// 40 days worked on 5 Oct 2026). Returns the format error, if any.
  Future<String?> syncDailyHealth(int days) => _fetch('queryDailyHealthData', {'days': days}, parseDailyHealth, db.saveDailyHealth);

  /// Height, weight, age and sex for the food targets (Mifflin-St Jeor), from Coros.
  Future<String?> syncProfile() => _fetch('queryUserInfo', {}, parseUserInfo, (UserProfile p) async {
        await db.setSetting(SettingKeys.nickname, p.nickname);
        if (p.heightCm != null) await db.setSetting(SettingKeys.heightCm, '${p.heightCm}');
        if (p.weightKg != null) await db.setSetting(SettingKeys.corosWeightKg, '${p.weightKg}');
        if (p.age != null) await db.setSetting(SettingKeys.age, '${p.age}');
        if (p.gender != null) await db.setSetting(SettingKeys.gender, p.gender!);
      });

  Map<String, dynamic> _recordsArgs(DateTime from, DateTime to, {int limit = 20}) => {
        'startDate': corosArgDate(from),
        'endDate': corosArgDate(to),
        'sportTypeCodes': [65535],
        'minDistanceKm': null,
        'maxDistanceKm': null,
        'minDurationMinutes': null,
        'maxDurationMinutes': null,
        'maxAveragePace': null,
        'locationKeyword': null,
        'limit': limit,
      };
}

class SettingKeys {
  static const easyRunHrCap = 'easy_run_hr_cap';
  static const wakeTime = 'wake_time'; // HH:mm
  static const restingHrRise = 'resting_hr_rise_bpm';
  static const sleepMinMinutes = 'sleep_min_minutes';
  static const restingHrHistoryDays = 'resting_hr_history_days';
  static const notificationsOn = 'notifications_on';
  static const historyImportedAt = 'history_imported_at';
  static const onboarded = 'onboarded';
  static const nickname = 'nickname';
  static const capSetAt = 'cap_set_at'; // for the threshold retest reminder
  static const weeklyReviewTime = 'weekly_review_time'; // HH:mm on Sundays
  static const weeklyNotifiedFor = 'weekly_notified_for'; // Monday of the last week notified

  // Food and body log (M4). Profile values come from Coros (queryUserInfo).
  static const heightCm = 'profile_height_cm';
  static const corosWeightKg = 'profile_weight_kg';
  static const age = 'profile_age';
  static const gender = 'profile_gender';
  static const carbsRest = 'food_carbs_rest_gkg';
  static const carbsEasy = 'food_carbs_easy_gkg';
  static const carbsHard = 'food_carbs_hard_gkg';
  static const proteinGkg = 'food_protein_gkg';
  static const deficitCap = 'food_deficit_cap_kcal';

  // Run map (M5).
  static const allActivitiesImportedAt = 'all_activities_imported_at';
  static const homeZoneLat = 'home_zone_lat';
  static const homeZoneLon = 'home_zone_lon';
  static const homeZoneRadiusM = 'home_zone_radius_m'; // 0 turns the zone off
  static const mapTilesKey = 'map_tiles_key'; // CARTO Basemaps key (L50)
  static const fitPausedUntil = 'fit_paused_until'; // after Coros's FIT limit (L53)
}
