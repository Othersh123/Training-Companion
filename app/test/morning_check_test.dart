import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:training_companion/coros/parsers.dart';
import 'package:training_companion/rules/morning_check.dart';

String fixture(String name) => File('test/fixtures/coros/$name').readAsStringSync();

/// Runs the morning check on the owner's real Coros history (fixtures from 2 Oct 2026).
MorningCheck checkOn(DateTime day, {int? cap, Source<Map<CorosDate, LoadDay>>? load, Source<Map<CorosDate, int?>>? rhr}) {
  return computeMorningCheck(
    today: day,
    hrv: Source.ok(parseSleepHrv(fixture('sleep_hrv_7d.txt'))),
    restingHr: rhr ?? Source.ok(parseRestingHr(fixture('resting_hr_30d.txt'))),
    sleep: Source.ok(parseSleepOverview(fixture('sleep_overview_7d.txt'))),
    load: load ?? Source.ok(parseTrainingLoad(fixture('training_load_7d.txt'))),
    activities: Source.ok(parseSportRecords(fixture('sport_records_18d.txt'))),
    easyRunHrCap: cap,
  );
}

SignalResult signal(MorningCheck c, Signal s) => c.signals.firstWhere((r) => r.signal == s);

void main() {
  test('27 Sep, the morning of the half marathon spike: short sleep and Excessive load mean Rest', () {
    final c = checkOn(DateTime(2026, 9, 27));
    expect(signal(c, Signal.sleep).state, SignalState.flagged);
    expect(signal(c, Signal.load).state, SignalState.flagged);
    expect(signal(c, Signal.hrv).state, SignalState.clear);
    expect(c.verdict, Verdict.rest);
    expect(c.reason, contains('Short night'));
  });

  test('1 Oct: HRV below range is one flag, so Go easy', () {
    final c = checkOn(DateTime(2026, 10, 1));
    expect(signal(c, Signal.hrv).state, SignalState.flagged);
    expect(signal(c, Signal.hrv).value, '91 ms');
    expect(signal(c, Signal.hrv).normal, '93 to 111 ms');
    expect(signal(c, Signal.restingHr).state, SignalState.clear);
    expect(signal(c, Signal.restingHr).normal, '30-day average 55 bpm');
    expect(signal(c, Signal.sleep).value, '7h 9m');
    expect(c.verdict, Verdict.goEasy);
  });

  test('30 Sep: Excessive load alone is Go easy', () {
    final c = checkOn(DateTime(2026, 9, 30));
    expect(signal(c, Signal.load).state, SignalState.flagged);
    expect(c.signals.where((s) => s.state == SignalState.flagged), hasLength(1));
    expect(c.verdict, Verdict.goEasy);
  });

  test('2 Oct, watch not worn overnight: a nap is not sleep, and one signal is not enough', () {
    final c = checkOn(DateTime(2026, 10, 2));
    expect(signal(c, Signal.sleep).state, SignalState.noData);
    expect(signal(c, Signal.hrv).state, SignalState.noData);
    expect(signal(c, Signal.restingHr).state, SignalState.noData);
    expect(signal(c, Signal.load).state, SignalState.clear);
    expect(c.verdict, Verdict.notEnoughData);
    expect(c.reason, 'Not enough data: missing HRV, Resting HR, Sleep');
  });

  test('a reply Coros changed is an error, never no data, and the rest still decide', () {
    final c = checkOn(DateTime(2026, 10, 1), load: const Source.failed('Coros format changed in queryTrainingLoadAssessment'));
    expect(signal(c, Signal.load).state, SignalState.error);
    expect(c.hasErrors, isTrue);
    expect(c.verdict, Verdict.goEasy);
  });

  test('resting HR 5+ bpm above the 30-day average is flagged', () {
    final rhr = parseRestingHr(fixture('resting_hr_30d.txt'))..['2026-10-01'] = 61;
    final c = checkOn(DateTime(2026, 10, 1), rhr: Source.ok(rhr));
    expect(signal(c, Signal.restingHr).state, SignalState.flagged);
    expect(signal(c, Signal.restingHr).note, 'Resting HR 61 bpm, 6 above your average');
    expect(c.verdict, Verdict.rest); // with low HRV, that's two flags
  });

  test('a "Low" HRV night is flagged like "Below normal"', () {
    final c = computeMorningCheck(
      today: DateTime(2026, 7, 16),
      hrv: Source.ok(parseSleepHrv(fixture('sleep_hrv_low_rating.txt'))),
      restingHr: const Source.ok({}),
      sleep: Source.ok(parseSleepOverview(fixture('sleep_overview_legacy.txt'))),
      load: const Source.ok({}),
      activities: const Source.ok([]),
    );
    expect(c.signals.firstWhere((s) => s.signal == Signal.hrv).state, SignalState.flagged);
  });

  test('resting HR without a week of history is no data, not a flag', () {
    final c = checkOn(DateTime(2026, 10, 1), rhr: const Source.ok({'2026-10-01': 70, '2026-09-30': 50}));
    expect(signal(c, Signal.restingHr).state, SignalState.noData);
  });

  group('yesterday\'s easy run', () {
    test('the 30 Sep home loop at 162 bpm is over a 150 cap', () {
      final run = checkOn(DateTime(2026, 10, 1), cap: 150).easyRun;
      expect(run.state, EasyRunState.overCap);
      expect(run.avgHr, 162);
      expect(run.runName, 'Outdoor Run');
    });

    test('the same run is under a 165 cap', () {
      expect(checkOn(DateTime(2026, 10, 1), cap: 165).easyRun.state, EasyRunState.underCap);
    });

    test('a half marathon is not an easy run', () {
      expect(checkOn(DateTime(2026, 9, 28), cap: 150).easyRun.state, EasyRunState.noEasyRun);
    });

    // M3: the plan's structure decides, when there is a plan that day.
    final plan = parsePlanDetails(fixture('training_plan_details_4d.txt'));
    ScheduledWorkout planned(String date) {
      final c = plan.days[date]!.single;
      return ScheduledWorkout(name: c.name, sport: c.sport, courseJson: c.courseJson);
    }

    test('a run the plan called easy is checked, however long it took', () {
      final c = computeMorningCheck(
        today: DateTime(2026, 10, 1),
        hrv: const Source.ok({}),
        restingHr: const Source.ok({}),
        sleep: const Source.ok({}),
        load: const Source.ok({}),
        activities: Source.ok(parseSportRecords(fixture('sport_records_18d.txt'))),
        easyRunHrCap: 150,
        // Pretend the 30 Sep run was the plan's "7k Easy + 6 Strides".
        plannedYesterday: [planned('2026-10-01')],
      );
      expect(c.easyRun.state, EasyRunState.overCap);
    });

    test('a run the plan called long is not an easy run', () {
      final c = computeMorningCheck(
        today: DateTime(2026, 10, 1),
        hrv: const Source.ok({}),
        restingHr: const Source.ok({}),
        sleep: const Source.ok({}),
        load: const Source.ok({}),
        activities: Source.ok(parseSportRecords(fixture('sport_records_18d.txt'))),
        easyRunHrCap: 150,
        plannedYesterday: [planned('2026-10-04')].map((w) => ScheduledWorkout(name: '23k Long Run', sport: w.sport, courseJson: w.courseJson)).toList(),
      );
      expect(c.easyRun.state, EasyRunState.noEasyRun);
    });

    test('without a cap set, says so', () {
      expect(checkOn(DateTime(2026, 10, 1)).easyRun.state, EasyRunState.capNotSet);
    });
  });
}
