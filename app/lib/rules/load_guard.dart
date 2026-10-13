/// The load guard (PRD: Core logic, Load guard), run over a plan the app follows.
/// Past days use what was actually run; today and later use the plan. Pure Dart.
library;

import 'dart:math' as math;

import '../coros/parsers.dart';
import 'planned_workout.dart';
import 'weekly_review.dart' show mondayOf;

enum GuardRule { volume, longRunGrowth, longRunShare, recoveryWeek, backToBack, postRace, taper, raceWeekGap, planGap }

class GuardWarning {
  GuardWarning(this.rule, this.monday, this.text);
  final GuardRule rule;
  final DateTime monday;
  final String text;
}

class GuardWeek {
  GuardWeek({required this.monday, required this.km, required this.longKm, required this.workouts, required this.past, required this.warnings});
  final DateTime monday;

  /// Actual km for days already gone, estimated planned km for the rest.
  final double km;
  final double longKm;
  final List<PlannedWorkout> workouts;

  /// Entirely before this week: actual running only.
  final bool past;
  final List<GuardWarning> warnings;
}

class GuardSettings {
  const GuardSettings({
    this.volumeRisePercent = 10,
    this.longRunGrowthKm = 2,
    this.longRunMaxShare = 0.35,
    this.recoveryEvery = 4,
    this.recoveryRatio = 0.8,
    this.postRaceEasyDays = 7,
    this.taperWeek1 = 0.80,
    this.taperWeek2 = 0.55,
  });

  /// Trail ultras (owner, 5 Oct 2026): long runs carry more of the week than in road plans,
  /// so the long run may be up to half the week. The other rules stay the same.
  const GuardSettings.trailUltra() : this(longRunMaxShare: 0.50);

  /// The settings for the primary race goal.
  factory GuardSettings.forRace({required bool trail, required int? distanceMeters}) =>
      trail && (distanceMeters ?? 0) > 42195 ? const GuardSettings.trailUltra() : const GuardSettings();

  final int volumeRisePercent;
  final double longRunGrowthKm;
  final double longRunMaxShare;
  final int recoveryEvery;

  /// A week at or under this share of the week before counts as a recovery week.
  final double recoveryRatio;
  final int postRaceEasyDays;

  /// Taper (owner, 5 Oct 2026: 2 weeks): the 7 days before race week at about 75% of peak
  /// and race week at about 50%, with a 5-point tolerance.
  final double taperWeek1;
  final double taperWeek2;
}

class GuardResult {
  GuardResult(this.weeks);
  final List<GuardWeek> weeks;
  List<GuardWarning> get warnings => [for (final w in weeks) ...w.warnings];
}

String _km(double v) => '${v.toStringAsFixed(0)} km';

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
String _day(DateTime d) => '${_days[d.weekday - 1]} ${d.day}';

/// [planned] covers today to race day (from the plan); [runs] covers at least the 3 weeks before
/// this one. [raceDate] is the primary race goal's date, if there is one.
GuardResult runLoadGuard({
  required DateTime today,
  required Map<CorosDate, List<PlannedWorkout>> planned,
  required List<Activity> runs,
  DateTime? raceDate,
  GuardSettings s = const GuardSettings(),
}) {
  final day0 = DateTime(today.year, today.month, today.day);
  final thisMonday = mondayOf(day0);
  final lastPlanned = planned.keys.fold<String?>(null, (m, d) => m == null || d.compareTo(m) > 0 ? d : m);
  final end = raceDate ?? (lastPlanned == null ? thisMonday.add(const Duration(days: 6)) : DateTime.parse(lastPlanned));
  final lastMonday = mondayOf(end);

  double actualKm(CorosDate d) => runs.where((a) => a.isRun && a.date == d).fold(0.0, (sum, a) => sum + (a.distanceMeters ?? 0) / 1000);
  double actualLong(CorosDate d) => runs.where((a) => a.isRun && a.date == d).fold(0.0, (m, a) => math.max(m, (a.distanceMeters ?? 0) / 1000));

  GuardWeek week(DateTime monday) {
    var km = 0.0, longKm = 0.0;
    final workouts = <PlannedWorkout>[];
    for (var i = 0; i < 7; i++) {
      final day = monday.add(Duration(days: i));
      final key = corosDate(day);
      final dayPlan = planned[key] ?? const [];
      workouts.addAll(dayPlan);
      if (day.isBefore(day0)) {
        km += actualKm(key);
        longKm = math.max(longKm, actualLong(key));
      } else {
        km += dayPlan.fold(0.0, (sum, w) => sum + w.km);
        longKm = dayPlan.fold(longKm, (m, w) => math.max(m, w.km));
      }
    }
    return GuardWeek(monday: monday, km: km, longKm: longKm, workouts: workouts, past: monday.isBefore(thisMonday), warnings: []);
  }

  // Three past weeks for context, then this week to race week.
  final weeks = [
    for (var m = thisMonday.subtract(const Duration(days: 21)); !m.isAfter(lastMonday); m = m.add(const Duration(days: 7))) week(m),
  ];

  for (var i = 3; i < weeks.length; i++) {
    final w = weeks[i], prev = weeks[i - 1];
    void warn(GuardRule rule, String text) => w.warnings.add(GuardWarning(rule, w.monday, text));
    final inTaper = raceDate != null && !w.monday.isBefore(mondayOf(raceDate).subtract(const Duration(days: 7)));

    // 1. Weekly volume: no more than +10% on the biggest of the previous 3 weeks. Measured against
    // the biggest, not the average, so returning to normal after a recovery week isn't flagged
    // (owner's plan, 26 Oct after the 19 Oct cutback, 5 Oct 2026).
    final recent = [weeks[i - 1], weeks[i - 2], weeks[i - 3]];
    final top3 = recent.fold(0.0, (m, x) => math.max(m, x.km));
    final limit = top3 * (1 + s.volumeRisePercent / 100);
    if (top3 > 0 && w.km > limit + 0.5) {
      warn(GuardRule.volume,
          '${_km(w.km)} planned, ${((w.km / top3 - 1) * 100).toStringAsFixed(0)}% above your biggest recent week (${_km(top3)}). Keep it to about ${_km(limit)}.');
    }

    // 2. Long run: no more than 2 km past the longest of the previous 3 weeks (same reason)...
    final longest = recent.fold(0.0, (m, x) => math.max(m, x.longKm));
    if (longest > 0 && w.longKm > longest + s.longRunGrowthKm + 0.5) {
      warn(GuardRule.longRunGrowth,
          '${_km(w.longKm)} long run is ${_km(w.longKm - longest)} longer than your longest recent run (${_km(longest)}). Grow it by ${s.longRunGrowthKm.toStringAsFixed(0)} km at most: about ${_km(longest + s.longRunGrowthKm)}.');
    }
    // ...and stays at or under 35% of the week.
    if (w.km > 0 && w.longKm > w.km * s.longRunMaxShare + 0.5 && !inTaper) {
      warn(GuardRule.longRunShare,
          '${_km(w.longKm)} long run is ${(w.longKm / w.km * 100).toStringAsFixed(0)}% of the week\'s ${_km(w.km)}. Keep it to ${(s.longRunMaxShare * 100).toStringAsFixed(0)}% or less (about ${_km(w.km * s.longRunMaxShare)}), or add easy running on other days.');
    }

    // 3. Every 4th week is a recovery week at about 75% of the week before.
    var building = 0;
    for (var j = i; j > 0 && building < s.recoveryEvery; j--) {
      if (weeks[j].km > weeks[j - 1].km * s.recoveryRatio) {
        building++;
      } else {
        break;
      }
    }
    if (building >= s.recoveryEvery && !inTaper) {
      warn(GuardRule.recoveryWeek,
          '${s.recoveryEvery} weeks in a row without a recovery week. Make this one about 75% of last week: ${_km(prev.km * 0.75)}.');
    }

    // 4. No two long or hard days back to back.
    final heavy = w.workouts.where((p) => p.hard || p.long).toList();
    for (final p in heavy) {
      final next = corosDate(DateTime.parse(p.date).add(const Duration(days: 1)));
      final clash = [...w.workouts, ...?(i + 1 < weeks.length ? weeks[i + 1].workouts : null)]
          .where((q) => q.date == next && (q.hard || q.long));
      if (clash.isNotEmpty) {
        warn(GuardRule.backToBack,
            '${p.name} (${_day(DateTime.parse(p.date))}) and ${clash.first.name} (${_day(DateTime.parse(next))}) are back to back. Put an easy day or rest between them.');
      }
    }
  }

  if (raceDate != null) {
    final race = DateTime(raceDate.year, raceDate.month, raceDate.day);
    final raceKey = corosDate(race);
    final raceWeek = weeks.lastWhere((w) => !w.monday.isAfter(race), orElse: () => weeks.last);

    // 5. Race week must be planned at all (the plan may end early).
    final daysBefore = [for (var d = 1; d <= 7; d++) corosDate(race.subtract(Duration(days: d)))];
    final lastWorkout = planned.keys.where((d) => d.compareTo(raceKey) < 0).fold<String?>(null, (m, d) => m == null || d.compareTo(m) > 0 ? d : m);
    if (!daysBefore.any((d) => planned[d]?.isNotEmpty ?? false) && race.isAfter(day0)) {
      raceWeek.warnings.add(GuardWarning(GuardRule.raceWeekGap, raceWeek.monday,
          'Nothing is planned in the 7 days before race day${lastWorkout == null ? '' : ' (the plan ends ${_day(DateTime.parse(lastWorkout))})'}. Add 3 or 4 short easy runs with a few strides, and rest the 2 days before the race.'));
    }

    // 5b. Any week between now and race week with no running planned at all (the owner's
    // plan stops on 14 Nov, leaving 16 to 22 Nov empty).
    final peakSoFar = weeks.fold(0.0, (m, w) => math.max(m, w.km));
    for (final w in weeks) {
      if (w.past || !w.monday.isBefore(mondayOf(race)) || w.monday.add(const Duration(days: 6)).isBefore(day0)) continue;
      final runsPlanned = w.workouts.any((p) => p.sport == WorkoutSport.run || p.sport == WorkoutSport.trailRun);
      if (!runsPlanned) {
        final taper = !w.monday.isBefore(mondayOf(race.subtract(const Duration(days: 14))));
        w.warnings.add(GuardWarning(GuardRule.planGap, w.monday,
            'No runs are planned this week${lastWorkout == null ? '' : ' (the plan ends ${_day(DateTime.parse(lastWorkout))})'}.${taper && peakSoFar > 0 ? ' As a taper week, aim for about ${_km(peakSoFar * 0.75)}: easy runs and one shorter long run.' : ' Add the week in the Coros app.'}'));
      }
    }

    // 6. Taper: the 7 days before race week, and race week itself, step down from peak.
    double windowKm(int fromDays, int toDays) {
      var km = 0.0;
      for (var d = fromDays; d >= toDays; d--) {
        final day = race.subtract(Duration(days: d));
        final key = corosDate(day);
        km += day.isBefore(day0) ? actualKm(key) : (planned[key] ?? const []).fold(0.0, (sum, w) => sum + w.km);
      }
      return km;
    }

    final taperStart = race.subtract(const Duration(days: 14));
    final peak = weeks.where((w) => w.monday.isBefore(mondayOf(taperStart))).fold(0.0, (m, w) => math.max(m, w.km));
    final t1 = windowKm(14, 8), t2 = windowKm(7, 1);
    if (peak > 0 && t1 > peak * s.taperWeek1) {
      raceWeek.warnings.add(GuardWarning(GuardRule.taper, mondayOf(taperStart),
          'The week before race week has ${_km(t1)}, ${(t1 / peak * 100).toStringAsFixed(0)}% of your peak week (${_km(peak)}). Taper to about ${_km(peak * 0.75)}.'));
    }
    if (peak > 0 && t2 > peak * s.taperWeek2) {
      raceWeek.warnings.add(GuardWarning(GuardRule.taper, raceWeek.monday,
          'Race week has ${_km(t2)} before race day, ${(t2 / peak * 100).toStringAsFixed(0)}% of your peak week. Taper to about ${_km(peak * 0.5)}.'));
    }

    // 7. After the race, 7 days easy before any hard session.
    for (final entry in planned.entries) {
      final d = DateTime.parse(entry.key);
      final after = d.difference(race).inDays;
      if (after >= 1 && after <= s.postRaceEasyDays) {
        for (final p in entry.value.where((p) => p.hard)) {
          final w = weeks.lastWhere((w) => !w.monday.isAfter(d), orElse: () => weeks.last);
          w.warnings.add(GuardWarning(GuardRule.postRace, w.monday,
              '${p.name} on ${_day(d)} is $after day${after == 1 ? '' : 's'} after the race. Keep the first ${s.postRaceEasyDays} days easy.'));
        }
      }
    }
  }

  return GuardResult(weeks.where((w) => !w.past).toList());
}
