import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:training_companion/coros/parsers.dart';
import 'package:training_companion/data/goal.dart';
import 'package:training_companion/rules/goal_status.dart';
import 'package:training_companion/rules/insights.dart';
import 'package:training_companion/rules/planned_workout.dart';

String fixture(String name) => File('test/fixtures/coros/$name').readAsStringSync();

PlannedWorkout run(String date, double km, {bool long = false, bool hard = false, String name = 'Run'}) =>
    PlannedWorkout(date: date, name: name, sport: WorkoutSport.run, hard: hard, long: long, estimatedMeters: km * 1000);

Activity done(String date, double km, {int minutes = 50, int sport = 100}) => Activity(
      labelId: '$date-$km',
      sportType: sport,
      name: 'Outdoor Run',
      date: date,
      start: DateTime.parse('${date}T06:00:00'),
      end: DateTime.parse('${date}T07:00:00'),
      durationSeconds: minutes * 60,
      distanceMeters: (km * 1000).round(),
    );

void main() {
  final malnad = Goal(type: GoalType.race, name: 'Malnad 50K', date: DateTime(2026, 11, 27), distanceMeters: 50000, terrain: Terrain.trail);
  final today = DateTime(2026, 10, 7, 20);

  group('race status (owner: adherence plus benchmarks, 7 Oct 2026)', () {
    test('a 50K gets the first-50K long-run benchmark; a marathon gets none', () {
      expect(benchmarkFor(malnad)!.minKm, 30);
      expect(benchmarkFor(Goal(type: GoalType.race, name: 'M', date: DateTime(2026, 12, 1), distanceMeters: 42195)), isNull);
    });

    test('runs done as planned, but no 30 km run done or planned: Watch, with the reason', () {
      final s = raceStatus(goal: malnad, today: today, planned: {
        '2026-09-27': [run('2026-09-27', 10)],
        '2026-10-04': [run('2026-10-04', 11)],
        '2026-11-08': [run('2026-11-08', 24, long: true)],
      }, runs: [
        done('2026-09-27', 10),
        done('2026-10-04', 11),
      ]);
      expect(s.track, Track.watch);
      expect(s.headline, '51 days to go · taper from 13 Nov');
      expect(s.lines.first, contains('2 runs and 21 km, against 2 runs and 21 km planned'));
      expect(s.lines[1], contains("0 of 2 long runs of 30 km or 4 h+ done"));
      expect(s.lines[1], contains("your plan's longest is 24 km"));
      expect(s.lines, contains('No trail runs in the plan before a trail race.'));
      // Home's visual: one short line (the most important reason) and the numbers it draws.
      expect(s.short, 'Long runs short of 50K guidance');
      final v = s.visual as RaceVisual;
      expect([v.daysTo, v.longDone, v.longPlanned, v.longNeeded], [51, 0, 0, 2]);
      expect(v.kmShare, closeTo(1.0, 0.001));
      expect(v.taper, DateTime(2026, 11, 13));
    });

    test('two long runs planned before the taper: on track', () {
      final s = raceStatus(goal: malnad, today: today, planned: {
        '2026-10-04': [run('2026-10-04', 11)],
        '2026-10-25': [run('2026-10-25', 30, long: true)],
        '2026-11-08': [run('2026-11-08', 32, long: true)],
      }, runs: [done('2026-10-04', 11)]);
      expect(s.lines[1], '0 of 2 long runs of 30 km or 4 h+ done, 2 more planned by 13 Nov.');
    });

    test('a 4-hour trail run counts as a long run, whatever the distance', () {
      final s = raceStatus(goal: malnad, today: today, planned: {'2026-10-04': [run('2026-10-04', 11)]}, runs: [
        done('2026-10-04', 11),
        done('2026-09-20', 24, minutes: 245, sport: 102),
        done('2026-09-13', 31, minutes: 230),
      ]);
      expect(s.lines[1], contains('2 long runs of 30 km or 4 h+ done'));
    });

    test('half the planned runs missed: Off track', () {
      final s = raceStatus(goal: malnad, today: today, planned: {
        for (final d in ['2026-09-24', '2026-09-27', '2026-10-01', '2026-10-04']) d: [run(d, 10)],
      }, runs: [done('2026-10-04', 10)]);
      expect(s.track, Track.offTrack);
      expect(s.lines.first, 'Last 2 weeks: 1 of 4 runs, 10 km of 40 km planned.');
    });
  });

  group('weight status', () {
    final goal = Goal(type: GoalType.weight, name: 'Body weight', date: DateTime(2026, 12, 31), targetWeightKg: 72);

    test('one weigh-in: not enough for a trend, but the needed rate is shown', () {
      final s = weightStatus(goal: goal, today: today, weights: {'2026-10-05': 78.5}, currentAvg: 78.5);
      expect(s.track, Track.unknown);
      expect(s.lines.first, 'Needs 0.54 kg a week.');
    });

    test('losing fast enough: on track; too slowly: Watch with a projected date; gaining: Off track', () {
      Map<String, double> series(double perWeek) => {
            for (var d = 21; d >= 0; d -= 3) corosDate(today.subtract(Duration(days: d))): 78.5 + perWeek * d / 7 * -1 + 0,
          };
      expect(weightStatus(goal: goal, today: today, weights: series(-0.6), currentAvg: 78.0).track, Track.onTrack);
      final slow = weightStatus(goal: goal, today: today, weights: series(-0.2), currentAvg: 78.0);
      expect(slow.track, Track.watch);
      expect(slow.lines.first, contains('at this rate you reach 72.0 kg around'));
      expect(weightStatus(goal: goal, today: today, weights: series(0.3), currentAvg: 78.8).track, Track.offTrack);
    });

    test('a target faster than 1 kg a week says so', () {
      final quick = Goal(type: GoalType.weight, name: 'Body weight', date: DateTime(2026, 11, 7), targetWeightKg: 72);
      expect(weightStatus(goal: quick, today: today, weights: {}, currentAvg: 78.5).lines.first, contains('faster than the 0.5 to 1 kg a week'));
    });
  });

  test('consistency: on pace, last chance, or out of days', () {
    final g = Goal(type: GoalType.consistency, name: 'Consistency', runsPerWeek: 3, strengthPerWeek: 3);
    expect(consistencyStatus(goal: g, today: today, runsDone: 2, strengthDone: 0).track, Track.onTrack); // Wed: 5 days left
    expect(consistencyStatus(goal: g, today: DateTime(2026, 10, 9), runsDone: 2, strengthDone: 0).track, Track.watch); // Fri: 3 days, 3 to go
    expect(consistencyStatus(goal: g, today: DateTime(2026, 10, 10), runsDone: 2, strengthDone: 0).track, Track.offTrack);
    expect(consistencyStatus(goal: g, today: today, runsDone: 3, strengthDone: 3).lines.single, 'Done for the week.');
  });

  group('insights', () {
    List<Insight> insights({Map<String, HrvNight?> hrv = const {}, Map<String, SleepDay> sleep = const {}, List<Activity>? acts, List<PlannedWorkout> tomorrow = const []}) =>
        computeInsights(
          today: DateTime(2026, 10, 7),
          hrv: hrv,
          sleep: sleep,
          sleepMinMinutes: 360,
          restingHr: const {},
          activities: acts ?? [done('2026-10-01', 5, sport: 402)],
          plannedStrengthLast14: const [],
          tomorrow: tomorrow,
        );

    test('nothing to say: no insights', () {
      expect(insights(), isEmpty);
    });

    test('three short nights, no strength in 14 days, and a long run tomorrow', () {
      final out = insights(
        sleep: {for (final d in ['2026-10-07', '2026-10-06', '2026-10-04']) d: SleepDay(mainAsleepMinutes: 300, napMinutes: 0)},
        acts: [done('2026-10-05', 8)],
        tomorrow: [run('2026-10-08', 16, long: true, name: '15k Long Run')],
      );
      expect(out.map((i) => i.kind), [InsightKind.sleep, InsightKind.strength, InsightKind.tomorrow]);
      expect(out.last.text, startsWith('Tomorrow: 15k Long Run (about 16 km).'));
    });

    test('HRV below range on 3 of 7 nights (from real Coros replies)', () {
      final nights = parseSleepHrv(fixture('sleep_hrv_7d.txt'));
      final shifted = {
        for (final e in nights.entries) corosDate(DateTime(2026, 10, 7).subtract(Duration(days: DateTime(2026, 10, 1).difference(DateTime.parse(e.key)).inDays))): e.value,
      };
      final low = {for (final k in shifted.keys.take(3)) k: HrvNight(avgMs: 85, rating: HrvRating.belowNormal, rangeLowMs: 93, rangeHighMs: 111, baselineMs: 102)};
      expect(insights(hrv: {...shifted, ...low}).first.kind, InsightKind.hrv);
    });
  });
}
