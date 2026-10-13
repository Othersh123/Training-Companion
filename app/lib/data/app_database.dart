import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../coros/parsers.dart';
import '../rules/morning_check.dart';
import 'goal.dart';

/// The local SQLite database. Every screen and rule reads from here, so the app works offline.
/// Raw Coros replies are kept next to parsed values, so a fixed parser can re-read history (L5).
class AppDatabase {
  AppDatabase._(this.db, this.path);

  final Database db;

  /// Where the database file lives; the Drive backup copies it.
  final String path;

  /// 1: M1. 2: schedule keeps the plan link, sport and structure (L28). 3: lap data (M2).
  static const _version = 6; // 4: goals (M3). 5: food and body log (M4). 6: routes (M5)

  /// GPS routes from FIT files, simplified and delta-encoded (fit_route.dart). A failed
  /// download keeps its error so it isn't retried every run.
  static const _routesTable = '''CREATE TABLE routes(
      label_id TEXT PRIMARY KEY, points BLOB, point_count INTEGER NOT NULL DEFAULT 0, fetched_at TEXT NOT NULL, error TEXT)''';

  /// Foods hold IFCT and packaged foods once logged (for recents), and recipes. Meal entries
  /// copy their nutrients, so editing or removing a food never rewrites what was eaten.
  static const _foodTables = [
    '''CREATE TABLE foods(
        id INTEGER PRIMARY KEY AUTOINCREMENT, source TEXT NOT NULL, source_id TEXT, name TEXT NOT NULL, detail TEXT,
        kcal REAL NOT NULL, protein REAL NOT NULL, carbs REAL NOT NULL, fat REAL NOT NULL, fibre REAL NOT NULL DEFAULT 0,
        serving_g REAL, serving_name TEXT, servings INTEGER, last_used_at TEXT, archived INTEGER NOT NULL DEFAULT 0)''',
    'CREATE UNIQUE INDEX foods_source ON foods(source, source_id)',
    '''CREATE TABLE recipe_items(
        recipe_id INTEGER NOT NULL, position INTEGER NOT NULL, food_id INTEGER NOT NULL, grams REAL NOT NULL,
        PRIMARY KEY(recipe_id, position))''',
    '''CREATE TABLE meal_entries(
        id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, meal TEXT NOT NULL, food_id INTEGER, name TEXT NOT NULL,
        grams REAL NOT NULL, kcal REAL NOT NULL, protein REAL NOT NULL, carbs REAL NOT NULL, fat REAL NOT NULL,
        fibre REAL NOT NULL DEFAULT 0, serving_g REAL, created_at TEXT NOT NULL)''',
    'CREATE INDEX meal_entries_date ON meal_entries(date)',
    'CREATE TABLE saved_meals(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, created_at TEXT NOT NULL)',
    '''CREATE TABLE saved_meal_items(
        saved_meal_id INTEGER NOT NULL, position INTEGER NOT NULL, food_id INTEGER NOT NULL, grams REAL NOT NULL,
        PRIMARY KEY(saved_meal_id, position))''',
    'CREATE TABLE weights(date TEXT PRIMARY KEY, kg REAL NOT NULL)',
    'CREATE TABLE daily_health(date TEXT PRIMARY KEY, active_kcal INTEGER)',
  ];

  static const _goalsTable = '''CREATE TABLE goals(
      id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT NOT NULL, name TEXT NOT NULL, date TEXT, distance_m INTEGER,
      terrain TEXT, target_s INTEGER, target_weight REAL, runs_per_week INTEGER, strength_per_week INTEGER,
      is_primary INTEGER NOT NULL DEFAULT 0)''';

  static const _lapTables = [
    '''CREATE TABLE run_splits(
        label_id TEXT NOT NULL, idx INTEGER NOT NULL, distance_m REAL NOT NULL, seconds REAL NOT NULL, avg_hr INTEGER,
        PRIMARY KEY(label_id, idx))''',
    'CREATE TABLE strength_sessions(label_id TEXT PRIMARY KEY, body_parts TEXT NOT NULL, work_sets INTEGER NOT NULL, reps INTEGER NOT NULL)',
    'CREATE TABLE laps_fetched(label_id TEXT PRIMARY KEY, fetched_at TEXT NOT NULL)',
  ];

  /// The app and the background job share one native connection (L55): sqflite runs every
  /// database on a single native thread, so two connections to one file deadlocked whenever
  /// one waited on the other's lock. With one connection, sqflite queues work from either
  /// isolate around each other's transactions. Never close the shared connection from the
  /// background job: it would close the app's too (L26).
  /// [ownConnection] is for tests only: a fresh in-memory database per test.
  static Future<AppDatabase> open({DatabaseFactory? factory, String? path, bool ownConnection = false}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), 'training_companion.db');
    final db = await f.openDatabase(dbPath,
        options: OpenDatabaseOptions(
          version: _version,
          onCreate: _create,
          onUpgrade: _upgrade,
          singleInstance: !ownConnection,
        ));
    return AppDatabase._(db, dbPath);
  }

  // ---- one Coros check at a time (L46)

  static const _leaseKey = 'sync_lease';

  /// Takes the right to run a Coros check for [ttl], unless another runner holds an
  /// unexpired one. Shared through the database, so it works across the app and the
  /// background job's isolate. In a transaction, so two runners can't both take it.
  Future<bool> tryLease(String owner, {Duration ttl = const Duration(minutes: 3)}) => db.transaction((txn) async {
        final now = DateTime.now();
        final rows = await txn.query('settings', where: 'key = ?', whereArgs: [_leaseKey]);
        if (rows.isNotEmpty) {
          final parts = (rows.first['value'] as String).split('|');
          final until = DateTime.tryParse(parts.last);
          if (parts.first != owner && until != null && until.isAfter(now)) return false;
        }
        await txn.insert('settings', {'key': _leaseKey, 'value': '$owner|${now.add(ttl).toIso8601String()}'},
            conflictAlgorithm: ConflictAlgorithm.replace);
        return true;
      });

  Future<void> releaseLease(String owner) => db.delete('settings', where: 'key = ? AND value LIKE ?', whereArgs: [_leaseKey, '$owner|%']);

  /// True while another runner's lease is unexpired.
  Future<bool> leaseHeldByOther(String owner) async {
    final v = await setting(_leaseKey);
    if (v == null) return false;
    final parts = v.split('|');
    final until = DateTime.tryParse(parts.last);
    return parts.first != owner && until != null && until.isAfter(DateTime.now());
  }

  static Future<void> _upgrade(Database db, int from, int to) async {
    if (from < 2) {
      await db.execute('ALTER TABLE schedule ADD COLUMN plan_id TEXT');
      await db.execute("ALTER TABLE schedule ADD COLUMN sport TEXT NOT NULL DEFAULT 'unknown'");
      await db.execute('ALTER TABLE schedule ADD COLUMN course_json TEXT');
    }
    if (from < 3) {
      for (final sql in _lapTables) {
        await db.execute(sql);
      }
    }
    if (from < 4) await db.execute(_goalsTable);
    if (from < 5) {
      for (final sql in _foodTables) {
        await db.execute(sql);
      }
    }
    if (from < 6) await db.execute(_routesTable);
  }

  // ---- goals (M3)

  Future<List<Goal>> goals() async =>
      (await db.query('goals', orderBy: 'is_primary DESC, date')).map(Goal.fromRow).toList();

  Future<Goal?> primaryGoal() async => (await goals()).where((g) => g.primary).firstOrNull;

  /// Saves a goal. Marking one primary clears the flag on the others; the first goal is primary.
  Future<int> saveGoal(Goal g) async => db.transaction((txn) async {
        final count = Sqflite.firstIntValue(await txn.rawQuery('SELECT COUNT(*) FROM goals')) ?? 0;
        final row = g.toRow();
        if (count == 0 || (count == 1 && g.id != null)) row['is_primary'] = 1;
        if (row['is_primary'] == 1) await txn.update('goals', {'is_primary': 0});
        if (g.id == null) {
          row.remove('id');
          return txn.insert('goals', row);
        }
        await txn.update('goals', row, where: 'id = ?', whereArgs: [g.id]);
        return g.id!;
      });

  Future<void> deleteGoal(int id) async {
    await db.delete('goals', where: 'id = ?', whereArgs: [id]);
    // Keep exactly one primary while any goal remains.
    if (await primaryGoal() == null) {
      final first = (await goals()).firstOrNull;
      if (first != null) await db.update('goals', {'is_primary': 1}, where: 'id = ?', whereArgs: [first.id]);
    }
  }

  static Future<void> _create(Database db, int version) async {
    final batch = db.batch()
      ..execute('''CREATE TABLE raw_replies(
          id INTEGER PRIMARY KEY AUTOINCREMENT, tool TEXT NOT NULL, args TEXT NOT NULL,
          fetched_at TEXT NOT NULL, text TEXT NOT NULL, parse_error TEXT)''')
      ..execute('''CREATE TABLE hrv(
          date TEXT PRIMARY KEY, avg_ms INTEGER, rating TEXT, range_low INTEGER, range_high INTEGER, baseline INTEGER)''')
      ..execute('CREATE TABLE resting_hr(date TEXT PRIMARY KEY, bpm INTEGER)')
      ..execute('''CREATE TABLE sleep(
          date TEXT PRIMARY KEY, main_asleep_min INTEGER, main_period_min INTEGER, main_window TEXT, nap_min INTEGER NOT NULL)''')
      ..execute('''CREATE TABLE training_load(
          date TEXT PRIMARY KEY, label TEXT NOT NULL, short_term INTEGER NOT NULL, long_term INTEGER NOT NULL, ratio REAL NOT NULL)''')
      ..execute('''CREATE TABLE activities(
          label_id TEXT PRIMARY KEY, sport_type INTEGER NOT NULL, name TEXT NOT NULL, date TEXT NOT NULL,
          start_utc TEXT NOT NULL, end_utc TEXT NOT NULL, duration_s INTEGER NOT NULL, distance_m INTEGER,
          avg_hr INTEGER, location TEXT, start_lat REAL, start_lon REAL)''')
      ..execute('CREATE INDEX activities_date ON activities(date)')
      ..execute('''CREATE TABLE schedule(
          date TEXT NOT NULL, position INTEGER NOT NULL, name TEXT NOT NULL, distance_m INTEGER,
          estimated_s INTEGER, training_load INTEGER, plan_id TEXT, sport TEXT NOT NULL DEFAULT 'unknown',
          course_json TEXT, PRIMARY KEY(date, position))''')
      ..execute('''CREATE TABLE checks(
          date TEXT PRIMARY KEY, verdict TEXT NOT NULL, reason TEXT NOT NULL, signals TEXT NOT NULL,
          easy_run TEXT NOT NULL, computed_at TEXT NOT NULL, final INTEGER NOT NULL DEFAULT 0, notified INTEGER NOT NULL DEFAULT 0)''')
      ..execute('CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)')
      ..execute('CREATE TABLE error_log(id INTEGER PRIMARY KEY AUTOINCREMENT, at TEXT NOT NULL, source TEXT NOT NULL, message TEXT NOT NULL)');
    for (final sql in _lapTables) {
      batch.execute(sql);
    }
    batch.execute(_goalsTable);
    for (final sql in _foodTables) {
      batch.execute(sql);
    }
    batch.execute(_routesTable);
    await batch.commit(noResult: true);
  }

  // ---- lap data (M2)

  Future<Set<String>> lapsFetched(Iterable<String> labelIds) async {
    final ids = labelIds.toList();
    if (ids.isEmpty) return {};
    final rows = await db.query('laps_fetched', where: 'label_id IN (${List.filled(ids.length, '?').join(',')})', whereArgs: ids);
    return {for (final r in rows) r['label_id'] as String};
  }

  Future<void> saveSplits(String labelId, List<Split> splits) async {
    await db.transaction((txn) async {
      await txn.delete('run_splits', where: 'label_id = ?', whereArgs: [labelId]);
      for (var i = 0; i < splits.length; i++) {
        await txn.insert('run_splits',
            {'label_id': labelId, 'idx': i, 'distance_m': splits[i].distanceMeters, 'seconds': splits[i].seconds, 'avg_hr': splits[i].avgHr});
      }
      await txn.insert('laps_fetched', {'label_id': labelId, 'fetched_at': DateTime.now().toIso8601String()},
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> saveStrength(String labelId, StrengthSummary s) async {
    await db.transaction((txn) async {
      await txn.insert('strength_sessions', {'label_id': labelId, 'body_parts': s.bodyParts.join('|'), 'work_sets': s.workSets, 'reps': s.reps},
          conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('laps_fetched', {'label_id': labelId, 'fetched_at': DateTime.now().toIso8601String()},
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<Map<String, List<Split>>> splitsFor(Iterable<String> labelIds) async {
    final ids = labelIds.toList();
    if (ids.isEmpty) return {};
    final rows = await db.query('run_splits',
        where: 'label_id IN (${List.filled(ids.length, '?').join(',')})', whereArgs: ids, orderBy: 'label_id, idx');
    final result = <String, List<Split>>{};
    for (final r in rows) {
      result.putIfAbsent(r['label_id'] as String, () => []).add(Split(
            distanceMeters: (r['distance_m'] as num).toDouble(),
            seconds: (r['seconds'] as num).toDouble(),
            avgHr: r['avg_hr'] as int?,
          ));
    }
    return result;
  }

  Future<Map<String, StrengthSummary>> strengthFor(Iterable<String> labelIds) async {
    final ids = labelIds.toList();
    if (ids.isEmpty) return {};
    final rows = await db.query('strength_sessions', where: 'label_id IN (${List.filled(ids.length, '?').join(',')})', whereArgs: ids);
    return {
      for (final r in rows)
        r['label_id'] as String: StrengthSummary(
          bodyParts: (r['body_parts'] as String).split('|').where((p) => p.isNotEmpty).toSet(),
          workSets: r['work_sets'] as int,
          reps: r['reps'] as int,
        ),
    };
  }

  Future<void> close() => db.close();

  /// A consistent copy of the whole database, safe to take while the app is running.
  Future<void> snapshotTo(String target) => db.execute('VACUUM INTO ?', [target]);

  // ---- raw replies and errors

  Future<void> saveRaw(String tool, Map<String, dynamic> args, String text, {String? parseError}) => db.insert('raw_replies', {
        'tool': tool,
        'args': jsonEncode(args),
        'fetched_at': DateTime.now().toUtc().toIso8601String(),
        'text': text,
        'parse_error': parseError,
      });

  Future<void> logError(String source, String message) async {
    await db.insert('error_log', {'at': DateTime.now().toIso8601String(), 'source': source, 'message': message});
    // Keep the log bounded; it's for spotting silent failures, not an archive.
    await db.execute('DELETE FROM error_log WHERE id NOT IN (SELECT id FROM error_log ORDER BY id DESC LIMIT 500)');
  }

  Future<List<Map<String, Object?>>> errors({int limit = 200}) =>
      db.query('error_log', orderBy: 'id DESC', limit: limit);

  // ---- parsed Coros data (upserts, so re-syncing a range is safe)

  Future<void> saveHrv(Map<CorosDate, HrvNight?> nights) async {
    final batch = db.batch();
    nights.forEach((date, n) => batch.insert(
        'hrv',
        {
          'date': date,
          'avg_ms': n?.avgMs,
          'rating': n?.rating.name,
          'range_low': n?.rangeLowMs,
          'range_high': n?.rangeHighMs,
          'baseline': n?.baselineMs,
        },
        conflictAlgorithm: ConflictAlgorithm.replace));
    await batch.commit(noResult: true);
  }

  Future<Map<CorosDate, HrvNight?>> hrvBetween(CorosDate from, CorosDate to) async {
    final rows = await db.query('hrv', where: 'date BETWEEN ? AND ?', whereArgs: [from, to]);
    return {
      for (final r in rows)
        r['date'] as String: r['avg_ms'] == null
            ? null
            : HrvNight(
                avgMs: r['avg_ms'] as int,
                rating: HrvRating.values.byName(r['rating'] as String),
                rangeLowMs: r['range_low'] as int,
                rangeHighMs: r['range_high'] as int,
                baselineMs: r['baseline'] as int,
              ),
    };
  }

  Future<void> saveRestingHr(Map<CorosDate, int?> days) async {
    final batch = db.batch();
    days.forEach((date, bpm) => batch.insert('resting_hr', {'date': date, 'bpm': bpm}, conflictAlgorithm: ConflictAlgorithm.replace));
    await batch.commit(noResult: true);
  }

  Future<Map<CorosDate, int?>> restingHrBetween(CorosDate from, CorosDate to) async {
    final rows = await db.query('resting_hr', where: 'date BETWEEN ? AND ?', whereArgs: [from, to]);
    return {for (final r in rows) r['date'] as String: r['bpm'] as int?};
  }

  Future<void> saveSleep(Map<CorosDate, SleepDay> days) async {
    final batch = db.batch();
    days.forEach((date, s) => batch.insert(
        'sleep',
        {
          'date': date,
          'main_asleep_min': s.mainAsleepMinutes,
          'main_period_min': s.mainPeriodMinutes,
          'main_window': s.mainWindow,
          'nap_min': s.napMinutes,
        },
        conflictAlgorithm: ConflictAlgorithm.replace));
    await batch.commit(noResult: true);
  }

  Future<Map<CorosDate, SleepDay>> sleepBetween(CorosDate from, CorosDate to) async {
    final rows = await db.query('sleep', where: 'date BETWEEN ? AND ?', whereArgs: [from, to]);
    return {
      for (final r in rows)
        r['date'] as String: SleepDay(
          mainAsleepMinutes: r['main_asleep_min'] as int?,
          mainPeriodMinutes: r['main_period_min'] as int?,
          mainWindow: r['main_window'] as String?,
          napMinutes: r['nap_min'] as int,
        ),
    };
  }

  Future<void> saveLoad(Map<CorosDate, LoadDay> days) async {
    final batch = db.batch();
    days.forEach((date, d) => batch.insert(
        'training_load',
        {'date': date, 'label': d.label, 'short_term': d.shortTerm, 'long_term': d.longTerm, 'ratio': d.ratio},
        conflictAlgorithm: ConflictAlgorithm.replace));
    await batch.commit(noResult: true);
  }

  Future<Map<CorosDate, LoadDay>> loadBetween(CorosDate from, CorosDate to) async {
    final rows = await db.query('training_load', where: 'date BETWEEN ? AND ?', whereArgs: [from, to]);
    return {
      for (final r in rows)
        r['date'] as String: LoadDay(
          label: r['label'] as String,
          shortTerm: r['short_term'] as int,
          longTerm: r['long_term'] as int,
          ratio: (r['ratio'] as num).toDouble(),
        ),
    };
  }

  Future<void> saveActivities(List<Activity> list) async {
    final batch = db.batch();
    for (final a in list) {
      batch.insert(
          'activities',
          {
            'label_id': a.labelId,
            'sport_type': a.sportType,
            'name': a.name,
            'date': a.date,
            'start_utc': a.start.toIso8601String(),
            'end_utc': a.end.toIso8601String(),
            'duration_s': a.durationSeconds,
            'distance_m': a.distanceMeters,
            'avg_hr': a.avgHr,
            'location': a.location,
            'start_lat': a.startLat,
            'start_lon': a.startLon,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Activity>> activitiesBetween(CorosDate from, CorosDate to) async {
    final rows = await db.query('activities', where: 'date BETWEEN ? AND ?', whereArgs: [from, to], orderBy: 'start_utc DESC');
    return [
      for (final r in rows)
        Activity(
          labelId: r['label_id'] as String,
          sportType: r['sport_type'] as int,
          name: r['name'] as String,
          date: r['date'] as String,
          start: DateTime.parse(r['start_utc'] as String),
          end: DateTime.parse(r['end_utc'] as String),
          durationSeconds: r['duration_s'] as int,
          distanceMeters: r['distance_m'] as int?,
          avgHr: r['avg_hr'] as int?,
          location: r['location'] as String?,
          startLat: (r['start_lat'] as num?)?.toDouble(),
          startLon: (r['start_lon'] as num?)?.toDouble(),
        ),
    ];
  }

  /// Replaces the schedule for every date in [from]..[to], so removed workouts disappear,
  /// and for any other date in the reply (Coros may return more days than asked for).
  Future<void> saveSchedule(CorosDate from, CorosDate to, Map<CorosDate, List<ScheduledWorkout>> byDate) async {
    await db.transaction((txn) async {
      await txn.delete('schedule', where: 'date BETWEEN ? AND ?', whereArgs: [from, to]);
      for (final date in byDate.keys) {
        await txn.delete('schedule', where: 'date = ?', whereArgs: [date]);
      }
      for (final entry in byDate.entries) {
        for (var i = 0; i < entry.value.length; i++) {
          final w = entry.value[i];
          await txn.insert('schedule', {
            'date': entry.key,
            'position': i,
            'name': w.name,
            'distance_m': w.distanceMeters,
            'estimated_s': w.estimatedSeconds,
            'training_load': w.trainingLoad,
            'plan_id': w.planId,
            'sport': w.sport.name,
            'course_json': w.courseJson,
          });
        }
      }
    });
  }

  /// Swaps plan codes (S5724) for the plan's real workouts (L28). Within a date, the plan's
  /// courses line up in order with that plan's schedule entries.
  Future<void> applyPlanDetails(PlanDetails plan) async {
    await setSetting('plan:${plan.planId}', jsonEncode({'name': plan.name, 'start': plan.startDate, 'end': plan.endDate}));
    await db.transaction((txn) async {
      for (final entry in plan.days.entries) {
        final rows = await txn.query('schedule',
            where: 'date = ? AND plan_id = ?', whereArgs: [entry.key, plan.planId], orderBy: 'position');
        for (var i = 0; i < rows.length && i < entry.value.length; i++) {
          final c = entry.value[i];
          await txn.update('schedule', {'name': c.name, 'sport': c.sport.name, 'course_json': c.courseJson},
              where: 'date = ? AND position = ?', whereArgs: [entry.key, rows[i]['position']]);
        }
      }
    });
  }

  /// Name and dates of a Coros plan seen on the calendar: (name, start, end).
  Future<(String, CorosDate?, CorosDate?)?> planInfo(String planId) async {
    final raw = await setting('plan:$planId');
    if (raw == null) return null;
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return (j['name'] as String, j['start'] as String?, j['end'] as String?);
  }

  Future<List<ScheduledWorkout>> scheduleOn(CorosDate date) => scheduleBetween(date, date).then((m) => m[date] ?? []);

  Future<Map<CorosDate, List<ScheduledWorkout>>> scheduleBetween(CorosDate from, CorosDate to) async {
    final rows = await db.query('schedule', where: 'date BETWEEN ? AND ?', whereArgs: [from, to], orderBy: 'date, position');
    final result = <CorosDate, List<ScheduledWorkout>>{};
    for (final r in rows) {
      result.putIfAbsent(r['date'] as String, () => []).add(ScheduledWorkout(
            name: r['name'] as String,
            distanceMeters: r['distance_m'] as int?,
            estimatedSeconds: r['estimated_s'] as int?,
            trainingLoad: r['training_load'] as int?,
            planId: r['plan_id'] as String?,
            sport: WorkoutSport.values.asNameMap()[r['sport'] as String?] ?? WorkoutSport.unknown,
            courseJson: r['course_json'] as String?,
          ));
    }
    return result;
  }

  // ---- morning checks

  Future<void> saveCheck(MorningCheck c, {required bool isFinal}) => db.insert(
      'checks',
      {
        'date': c.date,
        'verdict': c.verdict.name,
        'reason': c.reason,
        'signals': jsonEncode([
          for (final s in c.signals)
            {'signal': s.signal.name, 'state': s.state.name, 'value': s.value, 'normal': s.normal, 'note': s.note},
        ]),
        'easy_run': jsonEncode({
          'state': c.easyRun.state.name,
          'avgHr': c.easyRun.avgHr,
          'cap': c.easyRun.cap,
          'runName': c.easyRun.runName,
        }),
        'computed_at': DateTime.now().toIso8601String(),
        'final': isFinal ? 1 : 0,
        'notified': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace);

  Future<StoredCheck?> checkOn(CorosDate date) async {
    final rows = await db.query('checks', where: 'date = ?', whereArgs: [date]);
    if (rows.isEmpty) return null;
    final r = rows.single;
    final easy = jsonDecode(r['easy_run'] as String) as Map<String, dynamic>;
    return StoredCheck(
      check: MorningCheck(
        date: r['date'] as String,
        verdict: Verdict.values.byName(r['verdict'] as String),
        reason: r['reason'] as String,
        signals: [
          for (final s in (jsonDecode(r['signals'] as String) as List).cast<Map<String, dynamic>>())
            SignalResult(Signal.values.byName(s['signal'] as String), SignalState.values.byName(s['state'] as String),
                value: s['value'] as String?, normal: s['normal'] as String?, note: s['note'] as String?),
        ],
        easyRun: EasyRunCheck(EasyRunState.values.byName(easy['state'] as String),
            avgHr: easy['avgHr'] as int?, cap: easy['cap'] as int?, runName: easy['runName'] as String?),
      ),
      computedAt: DateTime.parse(r['computed_at'] as String),
      isFinal: r['final'] == 1,
      notified: r['notified'] == 1,
    );
  }

  Future<void> markNotified(CorosDate date) => db.update('checks', {'notified': 1}, where: 'date = ?', whereArgs: [date]);

  // ---- settings

  Future<String?> setting(String key) async {
    final rows = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  Future<void> setSetting(String key, String value) =>
      db.insert('settings', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
}

class StoredCheck {
  StoredCheck({required this.check, required this.computedAt, required this.isFinal, required this.notified});

  final MorningCheck check;
  final DateTime computedAt;

  /// Final once last night's data has arrived or the morning window has closed.
  final bool isFinal;
  final bool notified;
}
