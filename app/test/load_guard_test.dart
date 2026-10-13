import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:training_companion/coros/parsers.dart';
import 'package:training_companion/rules/load_guard.dart';
import 'package:training_companion/rules/planned_workout.dart';

String fixture(String name) => File('test/fixtures/coros/$name').readAsStringSync();

/// The owner's Marathon Plan 430, 5 Oct to 1 Nov, as read on 5 Oct 2026, classified.
Map<CorosDate, List<PlannedWorkout>> plan() {
  final details = parsePlanDetails(fixture('training_plan_details_4w.txt'));
  return {
    for (final e in details.days.entries)
      e.key: [
        for (final c in e.value)
          classifyWorkout(e.key, ScheduledWorkout(name: c.name, sport: c.sport, courseJson: c.courseJson)),
      ],
  };
}

PlannedWorkout one(String date) => plan()[date]!.first;

void main() {
  group('reading plan workouts', () {
    test('an easy run with strides is easy: 20-second Zone 5 strides are not hard', () {
      final w = one('2026-10-08');
      expect(w.name, '7k Easy + 6 Strides');
      expect(w.hard, isFalse);
      expect(w.isEasyRun, isTrue);
    });

    test('distance comes from the structure, not the name: "7k Easy" on 13 Oct is set to 10 km', () {
      final w = one('2026-10-13');
      expect(w.name, '7k Easy');
      expect(w.km, closeTo(11.3, 0.1)); // 10 km plus 5-minute warm-up and cool-down at easy pace
    });

    test('long runs and hard sessions', () {
      expect(one('2026-10-18').long, isTrue); // 23k Long Run
      expect(one('2026-10-18').hard, isFalse);
      expect(one('2026-10-29').hard, isTrue); // Threshold Workout: 4 km at Zone 3
      final mp = one('2026-11-01');
      expect(mp.hard && mp.long, isTrue); // Marathon Pace Run: 14 km at Zone 3, 22 km total
      expect(mp.kindLabel, 'Long, hard');
    });

    test('strength days are strength, with no distance', () {
      final strength = plan()['2026-10-06']!.last;
      expect(strength.name, 'Leg Strength Training');
      expect(strength.sport, WorkoutSport.strength);
      expect(strength.estimatedMeters, isNull);
    });
  });

  group('load guard on Marathon Plan 430 (5 Oct 2026)', () {
    final runs = parseSportRecords(fixture('sport_records_18d.txt'));
    late GuardResult result;
    setUp(() => result = runLoadGuard(today: DateTime(2026, 10, 5), planned: plan(), runs: runs, raceDate: DateTime(2026, 11, 27)));

    GuardWeek weekOf(int month, int day) => result.weeks.firstWhere((w) => w.monday == DateTime(2026, month, day));
    Iterable<GuardRule> rules(GuardWeek w) => w.warnings.map((x) => x.rule);

    test('weeks run from this week to race week', () {
      expect(result.weeks.first.monday, DateTime(2026, 10, 5));
      expect(result.weeks.last.monday, DateTime(2026, 11, 23));
    });

    test('12 to 18 Oct: the 15k to 23k long-run jump is flagged on growth and share', () {
      final w = weekOf(10, 12);
      expect(w.longKm, closeTo(24.3, 0.1));
      expect(rules(w), containsAll([GuardRule.longRunGrowth, GuardRule.longRunShare]));
      final growth = w.warnings.firstWhere((x) => x.rule == GuardRule.longRunGrowth);
      // Measured against the longest of the 3 weeks before (a 21 km run on 21 Sep), not just last week.
      expect(growth.text, contains('3 km longer than your longest recent run (21 km)'));
    });

    test('for a trail ultra the long run may be half the week (owner, 5 Oct 2026)', () {
      final ultra = runLoadGuard(
          today: DateTime(2026, 10, 5), planned: plan(), runs: runs, raceDate: DateTime(2026, 11, 27), s: const GuardSettings.trailUltra());
      final oct12 = ultra.weeks.firstWhere((w) => w.monday == DateTime(2026, 10, 12));
      expect(oct12.warnings.map((x) => x.rule), isNot(contains(GuardRule.longRunShare))); // 45% is fine now
      expect(oct12.warnings.map((x) => x.rule), contains(GuardRule.longRunGrowth)); // the other rules are unchanged
    });

    test('only trail races longer than a marathon count as ultras', () {
      expect(GuardSettings.forRace(trail: true, distanceMeters: 50000).longRunMaxShare, 0.50);
      expect(GuardSettings.forRace(trail: true, distanceMeters: 42195).longRunMaxShare, 0.35);
      expect(GuardSettings.forRace(trail: false, distanceMeters: 50000).longRunMaxShare, 0.35);
    });

    test('26 Oct returns to normal after the cutback: no volume or long-run growth warning (5 Oct 2026, phone)', () {
      final w = weekOf(10, 26);
      expect(rules(w), isNot(contains(GuardRule.volume)));
      expect(rules(w), isNot(contains(GuardRule.longRunGrowth)));
    });

    test('a week with no runs planned before race week is flagged; in the taper it gives a target', () {
      expect(rules(weekOf(11, 2)), contains(GuardRule.planGap)); // the 4-week fixture ends 1 Nov
      final taper = weekOf(11, 16).warnings.firstWhere((x) => x.rule == GuardRule.planGap);
      expect(taper.text, contains('As a taper week, aim for about'));
      expect(rules(weekOf(11, 23)), isNot(contains(GuardRule.planGap))); // race week has its own warning
      expect(rules(weekOf(10, 19)), isNot(contains(GuardRule.planGap)));
    });

    test('19 to 25 Oct is a cutback and raises no volume or long-run warnings', () {
      final w = weekOf(10, 19);
      expect(rules(w), isNot(contains(GuardRule.volume)));
      expect(rules(w), isNot(contains(GuardRule.longRunGrowth)));
    });

    test('the plan ends on 21 Nov, so race week is flagged as unplanned', () {
      final race = weekOf(11, 23);
      final gap = race.warnings.firstWhere((x) => x.rule == GuardRule.raceWeekGap);
      expect(gap.text, startsWith('Nothing is planned in the 7 days before race day'));
    });

    test('this week uses the plan for today onwards', () {
      expect(weekOf(10, 5).km, closeTo(43.6, 0.2));
    });
  });

  group('rules on synthetic plans', () {
    PlannedWorkout w(String date, double km, {bool hard = false, bool long = false, String name = 'Run'}) =>
        PlannedWorkout(date: date, name: name, sport: WorkoutSport.run, hard: hard, long: long, estimatedMeters: km * 1000);

    test('two hard or long days in a row are flagged', () {
      final r = runLoadGuard(
        today: DateTime(2026, 10, 5),
        planned: {
          '2026-10-10': [w('2026-10-10', 10, hard: true, name: 'Tempo')],
          '2026-10-11': [w('2026-10-11', 20, long: true, name: 'Long Run')],
        },
        runs: const [],
      );
      final b2b = r.warnings.firstWhere((x) => x.rule == GuardRule.backToBack);
      expect(b2b.text, 'Tempo (Sat 10) and Long Run (Sun 11) are back to back. Put an easy day or rest between them.');
    });

    test('a hard session within 7 days after the race is flagged', () {
      final r = runLoadGuard(
        today: DateTime(2026, 11, 20),
        planned: {
          '2026-11-26': [w('2026-11-26', 5)],
          '2026-11-30': [w('2026-11-30', 8, hard: true, name: 'Intervals')],
        },
        runs: const [],
        raceDate: DateTime(2026, 11, 27),
      );
      expect(r.warnings.map((x) => x.rule), contains(GuardRule.postRace));
    });

    test('a taper that stays at peak volume is flagged', () {
      final planned = <CorosDate, List<PlannedWorkout>>{};
      for (var d = DateTime(2026, 10, 26); d.isBefore(DateTime(2026, 11, 27)); d = d.add(const Duration(days: 1))) {
        final key = corosDate(d);
        planned[key] = [w(key, 6)]; // 42 km every week, no taper
      }
      final r = runLoadGuard(today: DateTime(2026, 10, 26), planned: planned, runs: const [], raceDate: DateTime(2026, 11, 27));
      expect(r.warnings.where((x) => x.rule == GuardRule.taper), hasLength(2));
    });
  });
}
