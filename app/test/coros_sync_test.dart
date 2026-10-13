import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:training_companion/coros/parsers.dart';
import 'package:training_companion/data/app_database.dart';
import 'package:training_companion/data/food_store.dart';
import 'package:training_companion/data/map_store.dart';
import 'package:training_companion/data/goal.dart';
import 'package:training_companion/rules/load_guard.dart';
import 'package:training_companion/rules/morning_check.dart';
import 'package:training_companion/rules/weekly_review.dart';
import 'package:training_companion/sync/coros_sync.dart';

String fixture(String name) => File('test/fixtures/coros/$name').readAsStringSync();

/// Serves the saved real replies, as if Coros answered on the given morning.
class FixtureCoros implements ToolCaller {
  FixtureCoros({this.overrides = const {}, this.offline = false});

  final Map<String, String> overrides;
  final bool offline;
  final calls = <String>[];

  static const files = {
    'querySleepHrv': 'sleep_hrv_7d.txt',
    'queryRestingHeartRate': 'resting_hr_30d.txt',
    'querySleepOverview': 'sleep_overview_7d.txt',
    'queryTrainingLoadAssessment': 'training_load_7d.txt',
    'querySportRecords': 'sport_records_18d.txt',
    'queryTrainingSchedule': 'training_schedule_week.txt',
    'queryTrainingPlanDetails': 'training_plan_details_4d.txt',
    'queryDailyHealthData': 'daily_health_7d.txt',
    'queryUserInfo': 'user_info.txt',
  };

  @override
  Future<String> callTool(String name, Map<String, dynamic> args) async {
    calls.add(name);
    if (offline) throw const SocketException('Failed host lookup');
    if (overrides.containsKey(name)) return overrides[name]!;
    // The owner's Coros history starts in 2025 (7 Oct 2026).
    if (name == 'querySportRecords' && (args['startDate'] as String).compareTo('20250101') < 0) return fixture('sport_records_none.txt');
    if (name == 'queryActivityFitFileDownloadUrls') return fixture('fit_url.txt');
    if (name == 'queryActivityLapData') {
      return fixture(args['sportType'] == 402 ? 'laps_strength_2026-09-29.json' : 'laps_run_2026-09-30.json');
    }
    return fixture(files[name]!);
  }
}

void main() {
  late AppDatabase db;

  setUpAll(sqfliteFfiInit);
  setUp(() async => db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath));
  tearDown(() => db.close());

  test('a morning with last night in: verdict stored as final, workout and raw replies saved', () async {
    await db.setSetting(SettingKeys.easyRunHrCap, '150');
    final sync = CorosSync(db, FixtureCoros());

    final result = await sync.runMorningCheck(DateTime(2026, 10, 1, 7, 30), windowClosed: false);

    expect(result.check.verdict, Verdict.goEasy);
    expect(result.lastNightArrived, isTrue);
    expect(result.isFinal, isTrue);
    expect(result.check.easyRun.state, EasyRunState.overCap);

    final stored = (await db.checkOn('2026-10-01'))!;
    expect(stored.check.verdict, Verdict.goEasy);
    expect(stored.check.signals.map((s) => s.state), result.check.signals.map((s) => s.state));
    expect((await db.scheduleOn('2026-10-01')).single.name, '7k Easy + 6 Strides');
    expect(await db.db.query('raw_replies'), hasLength(9)); // six tools, the plan details, laps for yesterday's run, active calories
    expect(await db.errors(), isEmpty);
  });

  test('a morning before the watch syncs: not final, keep polling until the window closes', () async {
    final sync = CorosSync(db, FixtureCoros());

    final early = await sync.runMorningCheck(DateTime(2026, 10, 2, 7, 0), windowClosed: false);
    expect(early.check.verdict, Verdict.notEnoughData);
    expect(early.isFinal, isFalse);

    final late = await sync.runMorningCheck(DateTime(2026, 10, 2, 9, 0), windowClosed: true);
    expect(late.isFinal, isTrue);
    expect(late.lastNightArrived, isFalse);
  });

  test('a changed reply is stored, logged and shown as an error signal', () async {
    final changed = fixture('training_load_7d.txt').replaceAll('Load Ratio:', 'ACWR:');
    final sync = CorosSync(db, FixtureCoros(overrides: {'queryTrainingLoadAssessment': changed}));

    final result = await sync.runMorningCheck(DateTime(2026, 10, 1, 7, 30), windowClosed: false);

    expect(result.check.signals.firstWhere((s) => s.signal == Signal.load).state, SignalState.error);
    expect(result.check.verdict, Verdict.goEasy); // HRV, RHR and sleep still decide
    final raw = await db.db.query('raw_replies', where: 'parse_error IS NOT NULL');
    expect(raw.single['tool'], 'queryTrainingLoadAssessment');
    expect((await db.errors()).single['source'], 'parser');
  });

  test('Coros unreachable: nothing overwritten, error logged', () async {
    final good = CorosSync(db, FixtureCoros());
    await good.runMorningCheck(DateTime(2026, 10, 1, 7, 30), windowClosed: false);

    final offline = CorosSync(db, FixtureCoros(offline: true));
    await expectLater(offline.runMorningCheck(DateTime(2026, 10, 1, 8, 0), windowClosed: false), throwsA(isA<CorosUnreachable>()));

    expect((await db.checkOn('2026-10-01'))!.check.verdict, Verdict.goEasy);
    expect((await db.errors()).first['source'], 'sync');
  });

  test('history import goes in small chunks and is safe to repeat', () async {
    final coros = FixtureCoros();
    final sync = CorosSync(db, coros);

    await sync.importHistory(DateTime(2026, 10, 2));
    await sync.importHistory(DateTime(2026, 10, 2));

    expect(coros.calls.where((c) => c == 'querySleepHrv').length, 2 * 13); // 7-day chunks over 12 weeks
    expect(await db.db.query('activities'), hasLength(12)); // no duplicates on re-import
    expect(await db.setting(SettingKeys.historyImportedAt), isNotNull);
  });

  test('plan codes on the calendar become the plan\'s real workouts (L28)', () async {
    final coros = FixtureCoros();
    await CorosSync(db, coros).runMorningCheck(DateTime(2026, 10, 2, 7, 0), windowClosed: false);

    final today = (await db.scheduleOn('2026-10-02')).single;
    expect(today.name, 'Core Workout');
    expect(today.sport, WorkoutSport.strength);
    expect((await db.scheduleOn('2026-10-04')).single.name, '11k Easy');
    expect(coros.calls.where((c) => c == 'queryTrainingPlanDetails'), hasLength(1));
  });

  test('if plan details can\'t be read, the codes stay and the error is logged', () async {
    final sync = CorosSync(db, FixtureCoros(overrides: {'queryTrainingPlanDetails': 'Training Plan Detail\nsomething new'}));
    await sync.runMorningCheck(DateTime(2026, 10, 2, 7, 0), windowClosed: false);

    expect((await db.scheduleOn('2026-10-02')).single.name, 'S5724');
    expect((await db.errors()).first['message'], contains('queryTrainingPlanDetails'));
  });

  test('a database from M1 (version 1) upgrades and keeps its data', () async {
    final path = '${Directory.systemTemp.path}/tc_migration_${DateTime.now().microsecondsSinceEpoch}.db';
    final v1 = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (d, _) async {
            await d.execute('''CREATE TABLE schedule(
                date TEXT NOT NULL, position INTEGER NOT NULL, name TEXT NOT NULL, distance_m INTEGER,
                estimated_s INTEGER, training_load INTEGER, PRIMARY KEY(date, position))''');
            await d.insert('schedule', {'date': '2026-10-02', 'position': 0, 'name': 'S5724'});
          },
        ));
    await v1.close();

    final upgraded = await AppDatabase.open(factory: databaseFactoryFfi, path: path);
    final w = (await upgraded.scheduleOn('2026-10-02')).single;
    expect(w.name, 'S5724');
    expect(w.sport, WorkoutSport.unknown);
    expect(await upgraded.db.getVersion(), 6);
    expect(await upgraded.routes(), isEmpty); // version 6's routes table exists
    expect(await upgraded.goals(), isEmpty); // version 4's goals table exists
    expect(await upgraded.entriesOn('2026-10-02'), isEmpty); // version 5's food tables exist
    expect(await upgraded.weightsBetween('2026-10-01', '2026-10-02'), isEmpty);
    expect(await upgraded.lapsFetched(['x']), isEmpty); // version 3's lap tables exist
    await upgraded.close();
    await File(path).delete();
  });

  test('syncing a week and reviewing it from the database (M2, 28 Sep to 4 Oct)', () async {
    await db.setSetting(SettingKeys.easyRunHrCap, '170');
    final coros = FixtureCoros();
    final sync = CorosSync(db, coros);
    final monday = DateTime(2026, 9, 28);

    await sync.syncWeek(monday, DateTime(2026, 10, 4, 19, 0));
    final r = await sync.weekReviewFromDatabase(monday);

    expect(r.runsDone, 1);
    expect(r.runsPlanned, 3);
    expect(r.strengthDone, 1);
    expect(r.bodyParts, {'Legs/Hips'});
    expect(r.excessiveDays, 3);
    expect(formatPace(r.fitness!.paceSecondsPerKm), '7:25');
    expect(r.oneThing.kind, ChangeKind.load);

    // Lap data is fetched once per activity, not on every sync.
    final lapCalls = coros.calls.where((c) => c == 'queryActivityLapData').length;
    await sync.syncWeek(monday, DateTime(2026, 10, 4, 19, 15));
    expect(coros.calls.where((c) => c == 'queryActivityLapData').length, lapCalls);
  });

  group('goals (M3)', () {
    test('the first goal is primary, a new primary replaces it, and deleting keeps one primary', () async {
      final malnad = await db.saveGoal(Goal(type: GoalType.race, name: 'Malnad 50K', date: DateTime(2026, 11, 27), distanceMeters: 50000, terrain: Terrain.trail));
      expect((await db.primaryGoal())!.name, 'Malnad 50K');

      await db.saveGoal(Goal(type: GoalType.consistency, name: 'Consistency', runsPerWeek: 4, strengthPerWeek: 2, primary: true));
      expect((await db.primaryGoal())!.name, 'Consistency');

      final consistency = (await db.goals()).firstWhere((g) => g.name == 'Consistency');
      await db.deleteGoal(consistency.id!);
      expect((await db.primaryGoal())!.id, malnad);
    });

    test('the guard reads the plan and the race goal from the database', () async {
      await db.saveGoal(Goal(type: GoalType.race, name: 'Malnad 50K', date: DateTime(2026, 11, 27), distanceMeters: 50000, terrain: Terrain.trail));
      final details = parsePlanDetails(fixture('training_plan_details_4w.txt'));
      await db.saveSchedule('2026-10-05', '2026-11-01', {
        for (final e in details.days.entries)
          e.key: [for (final c in e.value) ScheduledWorkout(name: c.name, sport: c.sport, courseJson: c.courseJson, planId: details.planId)],
      });
      await db.applyPlanDetails(details);

      final guard = await CorosSync(db, FixtureCoros()).guardFromDatabase(DateTime(2026, 10, 5));
      expect(guard.weeks.last.warnings.map((w) => w.rule), contains(GuardRule.raceWeekGap));
      // Malnad is a trail ultra, so the 23k at 45% of its week is within the relaxed limit.
      final oct12 = guard.weeks.firstWhere((w) => w.monday == DateTime(2026, 10, 12));
      expect(oct12.warnings.map((w) => w.rule), isNot(contains(GuardRule.longRunShare)));
      expect((await db.planInfo(details.planId))!.$1, 'Marathon Plan 430');
      expect((await db.planInfo(details.planId))!.$3, '2026-11-21');
    });
  });

  test('the morning check also stores active calories, and the profile sync stores height, age and sex (M4)', () async {
    final sync = CorosSync(db, FixtureCoros());
    await sync.runMorningCheck(DateTime(2026, 10, 2, 7, 30), windowClosed: false);
    expect((await db.activeKcalBetween('2026-09-27', '2026-09-27'))['2026-09-27'], 2976);
    await sync.syncProfile();
    expect(await db.setting(SettingKeys.heightCm), '175.0');
    expect(await db.setting(SettingKeys.age), '31');
    expect(await db.setting(SettingKeys.gender), 'Male');
  });

  test('app and background job share one connection: overlapping work never locks, one check at a time (L46, L55)', () async {
    final path = '${Directory.systemTemp.path}/tc_lease_${DateTime.now().microsecondsSinceEpoch}.db';
    final app = await AppDatabase.open(factory: databaseFactoryFfi, path: path);
    final background = await AppDatabase.open(factory: databaseFactoryFfi, path: path);
    expect(identical(app.db, background.db), isTrue); // one connection, not two (L55)

    // 6 Oct 2026: both saved Coros replies at the same moment and one hit "database is locked";
    // 13 Oct 2026: with two connections they deadlocked. A transaction on one side and writes on
    // the other now simply queue.
    await Future.wait([
      background.saveSchedule('2026-10-13', '2026-10-13', {
        '2026-10-13': [ScheduledWorkout(name: '7k Easy')],
      }),
      for (var i = 0; i < 40; i++) (i.isEven ? app : background).saveRaw('querySleepHrv', {'i': i}, 'reply $i'),
      app.setSetting('x', 'y'),
    ]);
    expect(await app.db.query('raw_replies'), hasLength(40));
    expect((await app.scheduleOn('2026-10-13')).single.name, '7k Easy');

    expect(await background.tryLease('background'), isTrue);
    expect(await app.tryLease('app'), isFalse); // Check now waits for the background run
    expect(await app.leaseHeldByOther('app'), isTrue);
    await background.releaseLease('background');
    expect(await app.leaseHeldByOther('app'), isFalse);
    expect(await app.tryLease('app'), isTrue);
    expect(await background.tryLease('background'), isFalse); // the background run skips
    await app.releaseLease('app');

    // An abandoned lease (the app was killed mid-check) expires.
    expect(await app.tryLease('app', ttl: const Duration(milliseconds: 1)), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(await background.tryLease('background'), isTrue);

    await app.close();
    await File(path).delete();
  });

  test('thresholds come from settings, with the confirmed defaults', () async {
    final sync = CorosSync(db, FixtureCoros());
    expect((await sync.thresholds()).sleepMinMinutes, 360);
    await db.setSetting(SettingKeys.sleepMinMinutes, '420');
    expect((await sync.thresholds()).sleepMinMinutes, 420);
  });
}
