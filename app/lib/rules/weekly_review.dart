/// The weekly review (PRD F3), from fixed rules. Pure Dart: reads parsed data only.
/// Decisions confirmed by the owner on 3 Oct 2026 are in the PRD under "Decisions for F3".
library;

import 'dart:math' as math;

import '../coros/parsers.dart';
import 'planned_workout.dart';

class ReviewSettings {
  const ReviewSettings({
    this.easyRunHrCap,
    this.easyRunMaxMinutes = 60,
    this.sleepMinMinutes = 6 * 60,
    this.homeRadiusKm = 25,
    this.fitnessBandBpm = 10,
    this.minBandSplits = 3,
    this.minEstimateSplits = 5,
    this.maxExtrapolationBpm = 15,
    this.volumeRisePercent = 10,
    this.complianceTarget = 0.8,
    this.defaultStrengthPerWeek = 2,
    this.shortNightsToFlag = 2,
  });

  final int? easyRunHrCap;
  final int easyRunMaxMinutes;
  final int sleepMinMinutes;
  final double homeRadiusKm;
  final int fitnessBandBpm;
  final int minBandSplits;
  final int minEstimateSplits;

  /// The estimate never projects further than this below the lowest HR it has data for.
  final int maxExtrapolationBpm;
  final int volumeRisePercent;
  final double complianceTarget;
  final int defaultStrengthPerWeek;
  final int shortNightsToFlag;
}

class FitnessReading {
  FitnessReading({required this.paceSecondsPerKm, required this.estimated, required this.splits, required this.bandLow, required this.bandHigh});

  final double paceSecondsPerKm;

  /// True when there weren't enough splits in the band and the pace comes from the
  /// week's pace-against-HR line at the cap.
  final bool estimated;
  final int splits;
  final int bandLow;
  final int bandHigh;
}

enum ChangeKind { load, volume, easyRuns, strength, sleep, onTrack }

class OneThing {
  OneThing(this.kind, this.text);
  final ChangeKind kind;
  final String text;
}

class WeekReview {
  WeekReview({
    required this.monday,
    required this.dailyKm,
    required this.dailyLoad,
    required this.kmRun,
    required this.longestRunKm,
    required this.runsDone,
    required this.runsPlanned,
    required this.strengthDone,
    required this.strengthPlanned,
    required this.strengthFromPlan,
    required this.bodyParts,
    required this.previousAvgKm,
    required this.easyRuns,
    required this.easyUnderCap,
    required this.excessiveDays,
    required this.fitness,
    required this.sleepAvgMinutes,
    required this.sleepNights,
    required this.shortNights,
    required this.restingHrAvg,
    required this.previousRestingHrAvg,
    required this.settings,
    required this.complete,
  });

  final DateTime monday;
  final List<double> dailyKm; // Monday first
  final List<LoadDay?> dailyLoad;
  final double kmRun;
  final double longestRunKm;
  final int runsDone;
  final int? runsPlanned;
  final int strengthDone;
  final int strengthPlanned;

  /// False when the target is the default 2 a week because nothing was planned.
  final bool strengthFromPlan;
  final Set<String> bodyParts;
  final double? previousAvgKm;
  final int easyRuns;
  final int easyUnderCap;
  final int excessiveDays;
  final FitnessReading? fitness;
  final int? sleepAvgMinutes;
  final int sleepNights;
  final int shortNights;
  final double? restingHrAvg;
  final double? previousRestingHrAvg;
  final ReviewSettings settings;

  /// False while the week is still in progress: totals are partial, so volume isn't
  /// compared and advice is about the rest of this week, not the next one.
  final bool complete;

  OneThing get oneThing => _oneThing(this, settings);

  double? get compliance => easyRuns == 0 ? null : easyUnderCap / easyRuns;

  /// Only for complete weeks; a partial week against full weeks means nothing.
  double? get volumeChangePercent =>
      !complete || previousAvgKm == null || previousAvgKm == 0 ? null : (kmRun - previousAvgKm!) / previousAvgKm! * 100;
}

/// Monday of the week containing [day].
DateTime mondayOf(DateTime day) => DateTime(day.year, day.month, day.day).subtract(Duration(days: day.weekday - 1));

/// The most common start point of road runs, to tell home runs from travel.
/// Start points are grouped to about 1 km (two decimal places).
(double, double)? homePoint(List<Activity> activities) {
  final starts = activities.where((a) => a.isRoadRun && a.startLat != null && a.startLon != null).toList();
  if (starts.isEmpty) return null;
  final cells = <String, List<Activity>>{};
  for (final a in starts) {
    cells.putIfAbsent('${a.startLat!.toStringAsFixed(2)},${a.startLon!.toStringAsFixed(2)}', () => []).add(a);
  }
  final top = cells.values.reduce((a, b) => b.length > a.length ? b : a);
  return (top.map((a) => a.startLat!).reduce((x, y) => x + y) / top.length, top.map((a) => a.startLon!).reduce((x, y) => x + y) / top.length);
}

double distanceKm((double, double) a, (double, double) b) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(b.$1 - a.$1), dLon = rad(b.$2 - a.$2);
  final h = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(a.$1)) * math.cos(rad(b.$1)) * math.pow(math.sin(dLon / 2), 2);
  return 2 * r * math.asin(math.sqrt(h));
}

/// [activities] must cover the review week and the 3 weeks before it, for the volume comparison.
WeekReview computeWeekReview({
  required DateTime monday,
  required List<Activity> activities,
  required Map<CorosDate, List<ScheduledWorkout>> schedule,
  required Map<String, List<Split>> splits,
  required Map<String, StrengthSummary> strength,
  required Map<CorosDate, SleepDay> sleep,
  required Map<CorosDate, int?> restingHr,
  required Map<CorosDate, LoadDay> load,
  (double, double)? home,
  ReviewSettings s = const ReviewSettings(),

  /// When the review is read; the week is complete once its Sunday has passed.
  DateTime? asOf,
}) {
  final days = [for (var i = 0; i < 7; i++) corosDate(monday.add(Duration(days: i)))];
  final inWeek = activities.where((a) => days.contains(a.date)).toList();
  final runs = inWeek.where((a) => a.isRun).toList();
  double km(Activity a) => (a.distanceMeters ?? 0) / 1000;

  final dailyKm = [for (final d in days) runs.where((a) => a.date == d).fold(0.0, (sum, a) => sum + km(a))];
  final kmRun = dailyKm.fold(0.0, (a, b) => a + b);
  final longest = runs.isEmpty ? 0.0 : runs.map(km).reduce(math.max);

  // Volume against the previous 3 weeks.
  final previousWeeks = [
    for (var w = 1; w <= 3; w++)
      () {
        final start = monday.subtract(Duration(days: 7 * w));
        final wDays = {for (var i = 0; i < 7; i++) corosDate(start.add(Duration(days: i)))};
        return activities.where((a) => a.isRun && wDays.contains(a.date)).fold(0.0, (sum, a) => sum + km(a));
      }(),
  ];
  final earliest = activities.map((a) => a.date).fold<String?>(null, (m, d) => m == null || d.compareTo(m) < 0 ? d : m);
  final historyCovers = earliest != null && earliest.compareTo(corosDate(monday.subtract(const Duration(days: 21)))) <= 0;
  final previousAvgKm = historyCovers ? previousWeeks.reduce((a, b) => a + b) / 3 : null;

  // Planned against done.
  final planned = [for (final d in days) ...?schedule[d]];
  final runsPlanned = planned.isEmpty ? null : planned.where((w) => w.sport == WorkoutSport.run || w.sport == WorkoutSport.trailRun).length;
  final strengthPlannedFromPlan = planned.where((w) => w.sport == WorkoutSport.strength).length;
  final strengthSessions = inWeek.where((a) => a.isStrength).toList();
  final bodyParts = {for (final a in strengthSessions) ...?strength[a.labelId]?.bodyParts};

  // Easy runs: the plan's label for that day when there is one (M3), else the duration rule.
  final easy = runs
      .where((a) => a.avgHr != null && (isPlannedEasyDay(a.date, schedule[a.date]) ?? a.durationSeconds < s.easyRunMaxMinutes * 60))
      .toList();
  final cap = s.easyRunHrCap;
  final easyUnder = cap == null ? 0 : easy.where((a) => a.avgHr! <= cap).length;

  final dailyLoad = [for (final d in days) load[d]];
  final excessive = dailyLoad.where((l) => l?.label == 'Excessive').length;

  // Recovery.
  final nights = [for (final d in days) sleep[d]?.mainAsleepMinutes].whereType<int>().toList();
  final shortNights = nights.where((m) => m < s.sleepMinMinutes).length;
  double? avg(Iterable<int?> xs) {
    final v = xs.whereType<int>().toList();
    return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
  }

  final prevDays = [for (var i = 1; i <= 7; i++) corosDate(monday.subtract(Duration(days: i)))];

  final fitness = _fitness(easy, splits, home, s);
  return WeekReview(
    monday: monday,
    dailyKm: dailyKm,
    dailyLoad: dailyLoad,
    kmRun: kmRun,
    longestRunKm: longest,
    runsDone: runs.length,
    runsPlanned: runsPlanned,
    strengthDone: strengthSessions.length,
    strengthPlanned: planned.isEmpty ? s.defaultStrengthPerWeek : strengthPlannedFromPlan,
    strengthFromPlan: planned.isNotEmpty,
    bodyParts: bodyParts,
    previousAvgKm: previousAvgKm,
    easyRuns: cap == null ? 0 : easy.length,
    easyUnderCap: easyUnder,
    excessiveDays: excessive,
    fitness: fitness,
    sleepAvgMinutes: nights.isEmpty ? null : (nights.reduce((a, b) => a + b) / nights.length).round(),
    sleepNights: nights.length,
    shortNights: shortNights,
    restingHrAvg: avg(days.map((d) => restingHr[d])),
    previousRestingHrAvg: avg(prevDays.map((d) => restingHr[d])),
    settings: s,
    complete: asOf == null || !asOf.isBefore(monday.add(const Duration(days: 7))),
  );
}

FitnessReading? _fitness(List<Activity> easyRuns, Map<String, List<Split>> splits, (double, double)? home, ReviewSettings s) {
  final cap = s.easyRunHrCap;
  if (cap == null) return null;
  final counted = easyRuns.where((a) {
    if (!a.isRoadRun) return false;
    if (home == null) return true;
    if (a.startLat == null || a.startLon == null) return false;
    return distanceKm(home, (a.startLat!, a.startLon!)) <= s.homeRadiusKm;
  });
  final all = [
    for (final a in counted)
      for (final sp in splits[a.labelId] ?? const <Split>[])
        if (sp.distanceMeters >= 950 && sp.avgHr != null) sp,
  ];
  final low = cap - s.fitnessBandBpm;
  final inBand = all.where((sp) => sp.avgHr! >= low && sp.avgHr! <= cap).map((sp) => sp.paceSecondsPerKm).toList()..sort();
  if (inBand.length >= s.minBandSplits) {
    final mid = inBand.length ~/ 2;
    final median = inBand.length.isOdd ? inBand[mid] : (inBand[mid - 1] + inBand[mid]) / 2;
    return FitnessReading(paceSecondsPerKm: median, estimated: false, splits: inBand.length, bandLow: low, bandHigh: cap);
  }
  // Estimate: least-squares line of pace against HR, read at the cap.
  if (all.length < s.minEstimateSplits) return null;
  final hrs = all.map((sp) => sp.avgHr!.toDouble()).toList();
  final paces = all.map((sp) => sp.paceSecondsPerKm).toList();
  final minHr = hrs.reduce(math.min), maxHr = hrs.reduce(math.max);
  if (maxHr - minHr < 5 || minHr - cap > s.maxExtrapolationBpm) return null;
  final n = all.length;
  final mx = hrs.reduce((a, b) => a + b) / n, my = paces.reduce((a, b) => a + b) / n;
  var sxy = 0.0, sxx = 0.0;
  for (var i = 0; i < n; i++) {
    sxy += (hrs[i] - mx) * (paces[i] - my);
    sxx += (hrs[i] - mx) * (hrs[i] - mx);
  }
  final pace = my + (sxy / sxx) * (cap - mx);
  return FitnessReading(paceSecondsPerKm: pace, estimated: true, splits: n, bandLow: low, bandHigh: cap);
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// ["Mon", "Tue", "Wed"] -> "Mon, Tue and Wed"
String _listJoin(List<String> items) =>
    items.length <= 1 ? items.join() : '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';

/// Owner's priority: load first, then easy runs, strength, sleep (PRD, Decisions for F3).
OneThing _oneThing(WeekReview r, ReviewSettings s) {
  if (r.excessiveDays > 0) {
    final days = '${r.excessiveDays} day${r.excessiveDays == 1 ? '' : 's'}';
    if (!r.complete) {
      // Mid-week, what matters is where load stands now, not how many days were high
      // (3 Oct 2026: Mon to Wed were Excessive, but it was back to Optimized by Thursday).
      final latest = r.dailyLoad.lastIndexWhere((l) => l != null);
      final excessiveNames = [
        for (var i = 0; i < 7; i++)
          if (r.dailyLoad[i]?.label == 'Excessive') _weekdays[i],
      ];
      if (latest >= 0 && r.dailyLoad[latest]!.label == 'Excessive') {
        final earlier = r.excessiveDays - 1;
        return OneThing(ChangeKind.load,
            'Coros rates your load Excessive today${earlier == 0 ? '' : ' (and on $earlier earlier day${earlier == 1 ? '' : 's'})'}. Keep it easy until it\'s back to Optimized.');
      }
      return OneThing(ChangeKind.load,
          'Your load was Excessive on ${_listJoin(excessiveNames)} and is back to ${r.dailyLoad[latest]!.label}. Train as planned, with an easy day after any hard one.');
    }
    // The ceiling is the recent weekly average, not this week's total (which may be tiny or huge).
    final ceiling = r.previousAvgKm ?? r.kmRun;
    return OneThing(ChangeKind.load,
        'Coros rated your load Excessive on $days. Keep next week to about ${ceiling.toStringAsFixed(0)} km'
        '${r.previousAvgKm == null ? '' : ', your recent weekly average,'} and follow every hard or long run with an easy day.');
  }
  final change = r.volumeChangePercent;
  if (change != null && change > s.volumeRisePercent) {
    final limit = r.previousAvgKm! * (1 + s.volumeRisePercent / 100);
    return OneThing(ChangeKind.volume,
        'You ran ${r.kmRun.toStringAsFixed(0)} km, ${change.toStringAsFixed(0)}% above your 3-week average of ${r.previousAvgKm!.toStringAsFixed(0)} km. Keep next week to about ${limit.toStringAsFixed(0)} km.');
  }
  final compliance = r.compliance;
  if (compliance != null && compliance < s.complianceTarget) {
    return OneThing(ChangeKind.easyRuns,
        'Only ${r.easyUnderCap} of ${r.easyRuns} easy runs stayed at or under ${s.easyRunHrCap} bpm. Slow the easy runs down, and walk the hills if you need to.');
  }
  if (r.strengthDone < r.strengthPlanned) {
    return OneThing(ChangeKind.strength,
        'You did ${r.strengthDone} of ${r.strengthPlanned} strength sessions. Put next week\'s in your calendar now.');
  }
  if (r.shortNights >= s.shortNightsToFlag) {
    return OneThing(ChangeKind.sleep,
        '${r.shortNights} nights under ${s.sleepMinMinutes ~/ 60} hours. Aim for an earlier night before your key sessions.');
  }
  return OneThing(ChangeKind.onTrack, 'Everything was on track. Keep next week as planned.');
}

/// 445 -> "7:25"
String formatPace(double secondsPerKm) {
  final total = secondsPerKm.round();
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}
