import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:training_companion/coros/parsers.dart';

String fixture(String name) => File('test/fixtures/coros/$name').readAsStringSync();

void main() {
  group('querySleepHrv', () {
    test('reads each night with Coros range and rating', () {
      final hrv = parseSleepHrv(fixture('sleep_hrv_7d.txt'));
      expect(hrv.keys, hasLength(6));
      final oct1 = hrv['2026-10-01']!;
      expect(oct1.avgMs, 91);
      expect(oct1.rating, HrvRating.belowNormal);
      expect([oct1.rangeLowMs, oct1.rangeHighMs, oct1.baselineMs], [93, 111, 102]);
      expect(hrv['2026-09-27']!.rating, HrvRating.aboveNormal);
    });

    test('a night left out of the assessment is absent, not an error', () {
      expect(parseSleepHrv(fixture('sleep_hrv_7d.txt')).containsKey('2026-10-02'), isFalse);
    });

    test('"No data" maps to null', () {
      final hrv = parseSleepHrv(fixture('sleep_hrv_1d_no_data.txt'));
      expect(hrv.containsKey('2026-10-02'), isTrue);
      expect(hrv['2026-10-02'], isNull);
    });

    test('a night with no time series at all is "No data", not a format error (4 Oct 2026)', () {
      final hrv = parseSleepHrv(fixture('sleep_hrv_no_nights.txt'));
      expect(hrv, {'2026-10-04': null});
    });

    test('an unknown rating is a format error, not a guess', () {
      final changed = fixture('sleep_hrv_7d.txt').replaceFirst('— Below normal', '— Very low');
      expect(() => parseSleepHrv(changed), throwsA(isA<CorosFormatException>()));
    });

    test('a renamed field is a format error', () {
      final changed = fixture('sleep_hrv_7d.txt').replaceAll('Normal Range:', 'Typical Range:');
      expect(() => parseSleepHrv(changed), throwsA(isA<CorosFormatException>()));
    });
  });

  group('querySleepHrv, older nights (12-week import, 2 Oct 2026)', () {
    test('"Low" is its own rating, below "Below normal"', () {
      final hrv = parseSleepHrv(fixture('sleep_hrv_low_rating.txt'));
      final jul16 = hrv['2026-07-16']!;
      expect(jul16.rating, HrvRating.low);
      expect(jul16.avgMs, 88);
      expect(jul16.rangeLowMs, 96);
      expect(hrv['2026-07-14']!.rating, HrvRating.belowNormal);
    });
  });

  group('querySleepOverview, older and missing nights (12-week import, 2 Oct 2026)', () {
    int dailyMinutes(String text, String date) {
      final lines = const LineSplitter().convert(text);
      final at = lines.indexOf(date);
      final daily = lines.skip(at).firstWhere((l) => l.startsWith('Daily Sleep: '));
      return parseMinutes('test', daily.substring('Daily Sleep: '.length).replaceAll('(incl. naps)', '').trim());
    }

    test('legacy "Main Sleep" is time in bed; asleep = Main Sleep minus Awake Time', () {
      final sleep = parseSleepOverview(fixture('sleep_overview_legacy.txt'));
      expect(sleep['2026-07-15']!.mainPeriodMinutes, 8 * 60 + 12);
      expect(sleep['2026-07-15']!.mainAsleepMinutes, 6 * 60 + 52);
      expect(sleep['2026-07-14']!.napMinutes, 21);
    });

    test('on every night in July and August, asleep plus naps equals Coros Daily Sleep', () {
      for (final name in ['sleep_overview_legacy.txt', 'sleep_overview_not_available.txt']) {
        final text = fixture(name);
        final sleep = parseSleepOverview(text);
        var checked = 0;
        sleep.forEach((date, day) {
          if (day.mainAsleepMinutes == null) return;
          final lines = const LineSplitter().convert(text);
          final block = lines.skip(lines.indexOf(date) + 1).takeWhile((l) => l.trim().isNotEmpty);
          if (!block.any((l) => l.startsWith('Daily Sleep: '))) return;
          expect(day.mainAsleepMinutes! + day.napMinutes, dailyMinutes(text, date), reason: '$name $date');
          checked++;
        });
        expect(checked, greaterThan(20), reason: name);
      }
    });

    test('"not available yet" is no data, not an error', () {
      final sleep = parseSleepOverview(fixture('sleep_overview_not_available.txt'));
      expect(sleep['2026-08-29']!.mainAsleepMinutes, isNull);
      expect(sleep['2026-08-28']!.mainAsleepMinutes, 6 * 60 + 38);
    });
  });

  group('queryRestingHeartRate', () {
    test('reads values and no-data days', () {
      final rhr = parseRestingHr(fixture('resting_hr_30d.txt'));
      expect(rhr, hasLength(30));
      expect(rhr['2026-10-01'], 51);
      expect(rhr['2026-09-05'], 63);
      expect(rhr['2026-10-02'], isNull);
      expect(rhr.values.where((v) => v == null), hasLength(7));
    });

    test('an unexpected line is a format error', () {
      final changed = fixture('resting_hr_30d.txt').replaceFirst('51 bpm', '51 beats');
      expect(() => parseRestingHr(changed), throwsA(isA<CorosFormatException>()));
    });
  });

  group('queryTrainingLoadAssessment', () {
    test('reads label, loads and ratio per day', () {
      final load = parseTrainingLoad(fixture('training_load_7d.txt'));
      expect(load, hasLength(7));
      expect(load['2026-10-02']!.label, 'Optimized');
      expect(load['2026-10-02']!.ratio, 1.32);
      expect(load['2026-09-27']!.label, 'Excessive');
      expect(load['2026-09-27']!.ratio, 2.11);
      expect(load.values.where((d) => d.label == 'Excessive'), hasLength(4));
    });

    test('a missing line is a format error', () {
      final changed = fixture('training_load_7d.txt').replaceFirst('Long-Term Load: 73\n', '');
      expect(() => parseTrainingLoad(changed), throwsA(isA<CorosFormatException>()));
    });
  });

  group('querySleepOverview', () {
    test('separates the night from naps', () {
      final sleep = parseSleepOverview(fixture('sleep_overview_7d.txt'));
      expect(sleep, hasLength(7));
      expect(sleep['2026-09-26']!.mainAsleepMinutes, 6 * 60 + 53);
      expect(sleep['2026-09-26']!.mainPeriodMinutes, 7 * 60 + 7);
      expect(sleep['2026-09-27']!.mainAsleepMinutes, 4 * 60 + 25);
    });

    test('a day with only a nap has no main sleep', () {
      final oct2 = parseSleepOverview(fixture('sleep_overview_7d.txt'))['2026-10-02']!;
      expect(oct2.mainAsleepMinutes, isNull);
      expect(oct2.napMinutes, 50);
    });
  });

  group('querySportRecords', () {
    late List<Activity> records;
    setUp(() => records = parseSportRecords(fixture('sport_records_18d.txt')));

    test('reads all records, including ones with a broken line', () {
      expect(records, hasLength(12));
      final strength = records.firstWhere((a) => a.date == '2026-09-29');
      expect(strength.sportType, 402);
      expect(strength.avgHr, 105);
      expect(strength.durationSeconds, 55 * 60 + 36);
    });

    test('reads runs with distance, HR, location and start point', () {
      final run = records.firstWhere((a) => a.date == '2026-09-30');
      expect(run.isRun, isTrue);
      expect(run.labelId, '480702293990211689');
      expect(run.distanceMeters, 5020);
      expect(run.avgHr, 162);
      expect(run.durationSeconds, 37 * 60 + 12);
      expect(run.location, 'Bangalore Run');
      expect(run.startLat, 13.541); // fixture coordinates moved 0.5 degrees for privacy
      final half = records.firstWhere((a) => a.date == '2026-09-27');
      expect(half.durationSeconds, 2 * 3600 + 28 * 60 + 59);
      expect(records.firstWhere((a) => a.sportType == 300).distanceMeters, 725);
    });

    test('a record count mismatch is a format error', () {
      final changed = fixture('sport_records_18d.txt').replaceFirst('(12 records)', '(13 records)');
      expect(() => parseSportRecords(changed), throwsA(isA<CorosFormatException>()));
    });
  });

  group('queryTrainingSchedule', () {
    test('reads workouts per day and keeps the plan link internally', () {
      final schedule = parseTrainingSchedule(fixture('training_schedule_week.txt'));
      expect(schedule.keys, ['2026-10-01', '2026-10-02', '2026-10-03', '2026-10-04']);
      final oct2 = schedule['2026-10-02']!.single;
      expect(oct2.name, 'S5724');
      expect(oct2.planId, '480727753751183759');
      expect(oct2.distanceMeters, isNull);
      expect(oct2.estimatedSeconds, 58 * 60 + 40);
      expect(schedule['2026-10-04']!.single.trainingLoad, 126);
    });

    test('a rest day is an empty schedule, not a format error (5 Oct 2026)', () {
      expect(parseTrainingSchedule(fixture('training_schedule_none.txt')), isEmpty);
    });

    test('other one-line replies are still format errors', () {
      expect(() => parseTrainingSchedule('No training schedule available.'), throwsA(isA<CorosFormatException>()));
    });
  });

  group('queryTrainingPlanDetails (L28)', () {
    test('gives the real names behind the schedule codes', () {
      final plan = parsePlanDetails(fixture('training_plan_details_4d.txt'));
      expect(plan.planId, '480727753751183759');
      expect(plan.name, 'Marathon Plan 430');
      expect([for (final d in plan.days.values) d.single.name], ['7k Easy + 6 Strides', 'Core Workout', '6k Easy', '11k Easy']);
    });

    test('takes the sport from Coros, including a strength day MCP marks as degraded', () {
      final plan = parsePlanDetails(fixture('training_plan_details_4d.txt'));
      expect(plan.days['2026-10-01']!.single.sport, WorkoutSport.run);
      expect(plan.days['2026-10-02']!.single.sport, WorkoutSport.strength);
      expect(plan.days['2026-10-02']!.single.status, 'Not started');
      expect(plan.days['2026-10-01']!.single.courseJson, contains('"repeats":6'));
    });

    test('a course without its JSON is a format error', () {
      final changed = fixture('training_plan_details_4d.txt').replaceFirst(RegExp(r'Course JSON: \{"dayNo":2[^\n]*'), '');
      expect(() => parsePlanDetails(changed), throwsA(isA<CorosFormatException>()));
    });
  });

  test('queryUserInfo reads nickname and body metrics', () {
    final u = parseUserInfo(fixture('user_info.txt'));
    expect(u.nickname, 'Adarsh');
    expect(u.heightCm, 175.0);
    expect(u.weightKg, 78.6);
    expect(u.age, 31);
  });

  group('durations', () {
    test('reads every format seen from Coros', () {
      expect(parseMinutes('t', '6h 53min'), 413);
      expect(parseMinutes('t', '50min'), 50);
      expect(parseMinutes('t', '55 min'), 55);
      expect(parseMinutes('t', '1h 0min'), 60);
      expect(parseClockSeconds('t', '2:28:59'), 8939);
      expect(() => parseMinutes('t', 'about an hour'), throwsA(isA<CorosFormatException>()));
    });
  });
}
