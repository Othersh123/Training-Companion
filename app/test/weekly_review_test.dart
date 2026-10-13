import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:training_companion/coros/parsers.dart';
import 'package:training_companion/rules/weekly_review.dart';

String fixture(String name) => File('test/fixtures/coros/$name').readAsStringSync();

/// The owner's real data from the fixtures (read 2 and 3 Oct 2026).
final activities = parseSportRecords(fixture('sport_records_18d.txt'));
const run30Sep = '480702293990211689';
const strength29Sep = '480702293990211688';

Map<CorosDate, List<ScheduledWorkout>> planWeek() {
  final schedule = parseTrainingSchedule(fixture('training_schedule_week.txt'));
  final plan = parsePlanDetails(fixture('training_plan_details_4d.txt'));
  return {
    for (final e in schedule.entries)
      e.key: [for (var i = 0; i < e.value.length; i++) e.value[i].withPlanCourse(plan.days[e.key]![i])],
  };
}

WeekReview review(DateTime monday,
    {int? cap = 145, List<Activity>? acts, Map<String, List<Split>>? splits, (double, double)? home, Map<CorosDate, List<ScheduledWorkout>>? schedule}) {
  final a = acts ?? activities;
  return computeWeekReview(
    monday: monday,
    activities: a,
    schedule: schedule ?? planWeek(),
    splits: splits ?? {run30Sep: parseRunSplits(fixture('laps_run_2026-09-30.json'))},
    strength: {strength29Sep: parseStrengthLaps(fixture('laps_strength_2026-09-29.json'))},
    sleep: parseSleepOverview(fixture('sleep_overview_7d.txt')),
    restingHr: parseRestingHr(fixture('resting_hr_30d.txt')),
    load: parseTrainingLoad(fixture('training_load_7d.txt')),
    home: home ?? homePoint(a),
    s: ReviewSettings(easyRunHrCap: cap),
  );
}

Activity run(String date, {required double km, required int minutes, required int hr, String id = 'x', double lat = 13.541, double lon = 78.129}) =>
    Activity(
      labelId: '$id$date',
      sportType: 100,
      name: 'Outdoor Run',
      date: date,
      start: DateTime.parse('${date}T00:00:00Z'),
      end: DateTime.parse('${date}T01:00:00Z'),
      durationSeconds: minutes * 60,
      distanceMeters: (km * 1000).round(),
      avgHr: hr,
      startLat: lat,
      startLon: lon,
    );

void main() {
  group('21 to 27 Sep, the half marathon week', () {
    late WeekReview r;
    setUp(() => r = review(DateTime(2026, 9, 21)));

    test('volume, longest run and sessions', () {
      expect(r.kmRun, closeTo(31.37, 0.01));
      expect(r.longestRunKm, closeTo(21.32, 0.01));
      expect(r.runsDone, 3);
      expect(r.dailyKm[6], closeTo(21.32, 0.01)); // the half was on Sunday 27 Sep
      expect(r.strengthDone, 2);
    });

    test('no plan that week: strength target is the default 2, runs planned unknown', () {
      expect(r.runsPlanned, isNull);
      expect(r.strengthPlanned, 2);
      expect(r.strengthFromPlan, isFalse);
    });

    test('both easy runs were over the 145 cap (148 and 162 bpm)', () {
      expect(r.easyRuns, 2);
      expect(r.easyUnderCap, 0);
      expect(r.compliance, 0);
    });

    test('an Excessive load day puts load first in the one thing to change', () {
      expect(r.excessiveDays, 1); // load fixture starts 26 Sep; 27 Sep was Excessive (2.11)
      expect(r.oneThing.kind, ChangeKind.load);
      expect(r.oneThing.text, contains('Excessive on 1 day.'));
      expect(r.oneThing.text, contains('31 km'));
    });

    test('without 3 earlier weeks of data, no volume comparison is made', () {
      expect(r.previousAvgKm, isNull);
      expect(r.volumeChangePercent, isNull);
    });

    test('recovery: sleep from the nights with data, resting HR against the week before', () {
      expect(r.sleepNights, 2); // sleep fixture starts 26 Sep
      expect(r.shortNights, 1); // the 4h 25m night before the half
      expect(r.sleepAvgMinutes, 339);
      expect(r.restingHrAvg, closeTo(51.25, 0.01));
      expect(r.previousRestingHrAvg, closeTo(54.6, 0.01));
    });
  });

  group('28 Sep to 4 Oct, Marathon Plan 430', () {
    test('planned sessions come from the plan, done from Coros, with body parts', () {
      final r = review(DateTime(2026, 9, 28));
      expect(r.excessiveDays, 3); // 28, 29 and 30 Sep
      expect(r.runsPlanned, 3);
      expect(r.strengthPlanned, 1);
      expect(r.strengthFromPlan, isTrue);
      expect(r.runsDone, 1);
      expect(r.strengthDone, 1);
      expect(r.bodyParts, {'Legs/Hips'});
    });

    test('fitness from real splits in the band: 4 of the 30 Sep splits are in 160 to 170 bpm', () {
      final f = review(DateTime(2026, 9, 28), cap: 170).fitness!;
      expect(f.estimated, isFalse);
      expect(f.splits, 4);
      expect(formatPace(f.paceSecondsPerKm), '7:25');
    });

    test('with the real 145 cap no split is in the band, so the pace is an estimate', () {
      final f = review(DateTime(2026, 9, 28)).fitness!;
      expect(f.estimated, isTrue);
      expect(f.splits, 5);
      expect(f.paceSecondsPerKm, inInclusiveRange(300, 600));
    });

    test('the short last split (16 m) is never counted', () {
      final f = review(DateTime(2026, 9, 28), cap: 175).fitness!;
      expect(f.splits, 5);
    });
  });

  group('a week still in progress (3 Oct 2026, the owner\'s question)', () {
    WeekReview midWeek({DateTime? asOf, String? loadUpTo}) => computeWeekReview(
          monday: DateTime(2026, 9, 28),
          activities: activities,
          schedule: planWeek(),
          splits: const {},
          strength: const {},
          sleep: parseSleepOverview(fixture('sleep_overview_7d.txt')),
          restingHr: parseRestingHr(fixture('resting_hr_30d.txt')),
          load: Map.fromEntries(parseTrainingLoad(fixture('training_load_7d.txt'))
              .entries
              .where((e) => loadUpTo == null || e.key.compareTo(loadUpTo) <= 0)),
          s: const ReviewSettings(easyRunHrCap: 145),
          asOf: asOf ?? DateTime(2026, 10, 3, 12, 0),
        );

    test('Saturday 3 Oct: load was Excessive Mon to Wed but is back to Optimized, so say so', () {
      final r = midWeek();
      expect(r.complete, isFalse);
      expect(r.oneThing.text,
          'Your load was Excessive on Mon, Tue and Wed and is back to Optimized. Train as planned, with an easy day after any hard one.');
      expect(r.oneThing.text, isNot(contains('5 km')));
    });

    test('while the latest load is still Excessive, say keep it easy until it drops', () {
      final r = midWeek(asOf: DateTime(2026, 9, 30, 20, 0), loadUpTo: '2026-09-30');
      expect(r.oneThing.text,
          'Coros rates your load Excessive today (and on 2 earlier days). Keep it easy until it\'s back to Optimized.');
    });

    test('no volume comparison while the week is partial', () {
      expect(midWeek().volumeChangePercent, isNull);
    });
  });

  group('fitness safeguards', () {
    final splits = parseRunSplits(fixture('laps_run_2026-09-30.json'));

    test('runs away from home are left out', () {
      final away = run('2026-09-30', km: 5, minutes: 37, hr: 162, id: 'away', lat: 13.387, lon: 75.35);
      final r = review(DateTime(2026, 9, 28), acts: [away], splits: {away.labelId: splits}, home: (13.541, 78.129));
      expect(r.fitness, isNull);
    });

    test('no estimate more than 15 bpm below the lowest split HR', () {
      final r = review(DateTime(2026, 9, 28), cap: 130); // lowest split is 150
      expect(r.fitness, isNull);
    });
  });

  group('one thing to change follows the owner\'s priority', () {
    final noPlan = <CorosDate, List<ScheduledWorkout>>{};
    // Three earlier weeks of 20 km each, then the review week (12 to 18 Oct; no load data).
    List<Activity> history(List<Activity> week) => [
          for (final d in ['2026-09-21', '2026-09-28', '2026-10-05']) run(d, km: 20, minutes: 120, hr: 150),
          ...week,
        ];

    test('volume more than 10% above the 3-week average', () {
      final r = review(DateTime(2026, 10, 12), acts: history([run('2026-10-14', km: 25, minutes: 150, hr: 150)]), schedule: noPlan);
      expect(r.previousAvgKm, 20);
      expect(r.oneThing.kind, ChangeKind.volume);
      expect(r.oneThing.text, contains('about 22 km'));
    });

    test('easy runs over the cap come next', () {
      final week = [run('2026-10-14', km: 5, minutes: 35, hr: 160), run('2026-10-16', km: 5, minutes: 35, hr: 140)];
      final r = review(DateTime(2026, 10, 12), acts: history(week), schedule: noPlan);
      expect(r.compliance, 0.5);
      expect(r.oneThing.kind, ChangeKind.easyRuns);
      expect(r.oneThing.text, contains('1 of 2 easy runs'));
    });

    test('then strength under plan', () {
      final week = [run('2026-10-14', km: 5, minutes: 35, hr: 140)];
      final r = review(DateTime(2026, 10, 12), acts: history(week), schedule: noPlan);
      expect(r.oneThing.kind, ChangeKind.strength);
      expect(r.oneThing.text, 'You did 0 of 2 strength sessions. Put next week\'s in your calendar now.');
    });
  });
}
