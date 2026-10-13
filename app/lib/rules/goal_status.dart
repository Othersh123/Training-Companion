import 'dart:math' as math;

import '../coros/parsers.dart';
import '../data/goal.dart';
import 'load_guard.dart';
import 'planned_workout.dart';
import 'weekly_review.dart' show FitnessReading, formatPace, mondayOf;

/// Home screen goal cards (owner, 7 Oct 2026): each goal gets a status and the reasons,
/// all from fixed rules over stored data.
enum Track { onTrack, watch, offTrack, unknown }

extension TrackLabel on Track {
  String get label => switch (this) {
        Track.onTrack => 'On track',
        Track.watch => 'Watch',
        Track.offTrack => 'Off track',
        Track.unknown => 'Not enough data',
      };
}

class GoalStatus {
  GoalStatus({required this.goal, required this.track, required this.headline, required this.lines, this.short = '', this.visual});
  final Goal goal;
  final Track track;

  /// "51 days to go", "78.4 kg, 6.4 kg to go".
  final String headline;

  /// The reasons, most important first. Shown in full on the Plan tab.
  final List<String> lines;

  /// One short line for Home (owner, 7 Oct 2026: Home visual, details on Plan).
  final String short;

  /// What Home draws: a [RaceVisual], [WeightVisual], [ConsistencyVisual] or [AerobicVisual].
  final Object? visual;
}

class RaceVisual {
  RaceVisual({
    required this.daysTo,
    required this.blockStart,
    required this.race,
    required this.taper,
    required this.kmShare,
    required this.longDone,
    required this.longPlanned,
    required this.longNeeded,
    required this.longestKm,
    required this.benchmarkKm,
  });
  final int daysTo;
  final DateTime blockStart, race, taper;

  /// Km done over km planned in the last 14 days; null without a plan.
  final double? kmShare;
  final int longDone, longPlanned;

  /// 0 when there's no benchmark for this race distance.
  final int longNeeded;

  /// Longest run in the last 16 weeks, and the benchmark distance (0 without one).
  final double longestKm, benchmarkKm;
}

class WeightVisual {
  WeightVisual({required this.start, required this.current, required this.target, required this.neededPerWeek, required this.spark});
  final double start, current, target, neededPerWeek;

  /// 7-day averages over the last 4 weeks, oldest first (nulls where none).
  final List<double?> spark;
}

class ConsistencyVisual {
  ConsistencyVisual({required this.runsDone, required this.runsTarget, required this.strengthDone, required this.strengthTarget, required this.daysLeft});
  final int runsDone, runsTarget, strengthDone, strengthTarget, daysLeft;
}

class AerobicVisual {
  AerobicVisual(this.paces);

  /// Seconds per km by week, oldest first.
  final List<double?> paces;
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _date(DateTime d) => '${d.day} ${_months[d.month - 1]}';
String _km(double v) => '${v.toStringAsFixed(0)} km';
DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Long-run benchmark for a race goal, or null where no sourced guidance applies.
class LongRunBenchmark {
  const LongRunBenchmark({required this.minKm, required this.minMinutes, required this.count, required this.daysBefore, required this.source});
  final double minKm;
  final int minMinutes;
  final int count;

  /// The last one done this many days before race day (the start of the taper).
  final int daysBefore;
  final String source;
}

/// First 50K, to finish: two or three long runs around 32 km (20 miles), or up to 4 hours on
/// trails (Marathon Handbook, "Ultramarathon long runs"; Hal Higdon's 50K plan peaks with three
/// 20-milers), the last about 2 weeks out, before the taper (Jeff Browning's 50K plan). Counted
/// from 30 km to allow for GPS and route differences. Other race distances: no benchmark.
LongRunBenchmark? benchmarkFor(Goal race) {
  final km = (race.distanceMeters ?? 0) / 1000;
  if (km > 42.2 && km <= 60) {
    return const LongRunBenchmark(minKm: 30, minMinutes: 240, count: 2, daysBefore: 14, source: 'first-50K guidance');
  }
  return null;
}

/// [planned] covers the 14 days before today and today to race day; [runs] covers at least
/// the 12 weeks before today. [guard] is the load guard over the plan to race day.
GoalStatus raceStatus({
  required Goal goal,
  required DateTime today,
  required Map<CorosDate, List<PlannedWorkout>> planned,
  required List<Activity> runs,
  GuardResult? guard,
  DateTime? blockStart,
}) {
  final day0 = _day(today);
  final race = _day(goal.date!);
  final daysTo = race.difference(day0).inDays;
  if (daysTo < 0) {
    return GoalStatus(goal: goal, track: Track.unknown, headline: 'Race day was ${_date(race)}', lines: ['Set your next goal on the Plan tab.'], short: 'Race day has passed');
  }
  final lines = <String>[];
  var track = Track.onTrack;
  void worse(Track t) {
    if (t.index > track.index) track = t;
  }

  // Home's one line: the most important reason (lower number wins).
  final shorts = <(int, String)>[];
  double? kmShareV;
  var longDone = 0, longAhead = 0, longNeeded = 0;
  var benchKm = 0.0;

  // Plan adherence over the last 14 days (today not counted: it may still happen).
  final from = day0.subtract(const Duration(days: 14));
  bool inWindow(String d) => d.compareTo(corosDate(from)) >= 0 && d.compareTo(corosDate(day0)) < 0;
  final plannedRuns = [for (final e in planned.entries) if (inWindow(e.key)) ...e.value.where((p) => p.isRun)];
  final doneRuns = runs.where((a) => a.isRun && inWindow(a.date)).toList();
  if (plannedRuns.isNotEmpty) {
    final plannedKm = plannedRuns.fold(0.0, (s, p) => s + p.km);
    final doneKm = doneRuns.fold(0.0, (s, a) => s + (a.distanceMeters ?? 0) / 1000);
    final runShare = doneRuns.length / plannedRuns.length;
    final kmShare = plannedKm == 0 ? 1.0 : doneKm / plannedKm;
    lines.add(doneRuns.length >= plannedRuns.length && doneKm >= plannedKm
        ? 'Last 2 weeks: ${doneRuns.length} runs and ${_km(doneKm)}, against ${plannedRuns.length} runs and ${_km(plannedKm)} planned.'
        : 'Last 2 weeks: ${doneRuns.length} of ${plannedRuns.length} runs, ${_km(doneKm)} of ${_km(plannedKm)} planned.');
    final share = math.min(runShare, kmShare);
    kmShareV = kmShare;
    if (share < 0.6) {
      worse(Track.offTrack);
      shorts.add((0, 'Behind plan: ${(share * 100).round()}% done in 2 weeks'));
    } else if (share < 0.8) {
      worse(Track.watch);
      shorts.add((3, 'A little behind plan'));
    }
  } else {
    lines.add('No runs were planned in the last 2 weeks.');
    worse(Track.watch);
    shorts.add((4, 'No runs planned lately'));
  }

  // Long-run benchmark (owner chose adherence plus benchmarks, 7 Oct 2026).
  final b = benchmarkFor(goal);
  if (b != null) {
    final deadline = race.subtract(Duration(days: b.daysBefore));
    final since = race.subtract(const Duration(days: 16 * 7));
    final done = runs
        .where((a) => a.isRun && !a.start.isBefore(since) && ((a.distanceMeters ?? 0) / 1000 >= b.minKm || a.durationSeconds >= b.minMinutes * 60))
        .length;
    final ahead = [
      for (final e in planned.entries)
        if (e.key.compareTo(corosDate(day0)) >= 0 && e.key.compareTo(corosDate(deadline)) <= 0) ...e.value.where((p) => p.isRun && p.km >= b.minKm),
    ].length;
    longDone = done;
    longAhead = ahead;
    longNeeded = b.count;
    benchKm = b.minKm;
    final what = 'long runs of ${b.minKm.round()} km or ${b.minMinutes ~/ 60} h+';
    if (done >= b.count) {
      lines.add('${b.count} $what done, as ${b.source} suggests.');
    } else if (done + ahead >= b.count) {
      lines.add('$done of ${b.count} $what done, $ahead more planned by ${_date(deadline)}.');
    } else {
      final longestPlanned = [
        for (final e in planned.entries)
          if (e.key.compareTo(corosDate(day0)) >= 0 && e.key.compareTo(corosDate(deadline)) <= 0) ...e.value.where((p) => p.isRun),
      ].fold(0.0, (m, p) => math.max(m, p.km));
      lines.add('$done of ${b.count} $what done${ahead > 0 ? ', $ahead planned' : ''}. '
          '${b.source[0].toUpperCase()}${b.source.substring(1)}: ${b.count} to 3 by ${_date(deadline)}'
          '${longestPlanned > 0 ? '; your plan\'s longest is ${_km(longestPlanned)}' : ''}.');
      worse(Track.watch);
      shorts.add((1, 'Long runs short of 50K guidance'));
    }
  }

  // Trail race on a road plan.
  if (goal.terrain == Terrain.trail && !planned.values.expand((d) => d).any((p) => p.sport == WorkoutSport.trailRun)) {
    lines.add('No trail runs in the plan before a trail race.');
    shorts.add((5, 'No trail runs planned'));
  }

  // The nearest guard warning ahead (the Plan tab has the full list).
  final next = guard?.warnings.where((w) => !w.monday.add(const Duration(days: 6)).isBefore(day0)).firstOrNull;
  if (next != null) {
    lines.add('Plan: ${next.text}');
    if (next.rule == GuardRule.raceWeekGap || next.rule == GuardRule.planGap) {
      worse(Track.watch);
      shorts.add((2, 'Gaps in the plan before race day'));
    } else {
      shorts.add((6, 'Plan check: see the Plan tab'));
    }
  }
  shorts.sort((a, b) => a.$1.compareTo(b.$1));

  final since = race.subtract(const Duration(days: 16 * 7));
  final longest = runs.where((a) => a.isRun && !a.start.isBefore(since)).fold(0.0, (m, a) => math.max(m, (a.distanceMeters ?? 0) / 1000));

  final taper = race.subtract(const Duration(days: 14));
  final when = daysTo == 0
      ? 'Race day'
      : !day0.isBefore(taper)
          ? '$daysTo days to go · taper'
          : '$daysTo days to go · taper from ${_date(taper)}';
  return GoalStatus(
    goal: goal,
    track: track,
    headline: when,
    lines: lines,
    short: shorts.isEmpty ? 'On plan' : shorts.first.$2,
    visual: RaceVisual(
      daysTo: daysTo,
      blockStart: blockStart ?? race.subtract(const Duration(days: 12 * 7)),
      race: race,
      taper: taper,
      kmShare: kmShareV,
      longDone: longDone,
      longPlanned: longAhead,
      longNeeded: longNeeded,
      longestKm: longest,
      benchmarkKm: benchKm,
    ),
  );
}

/// [weights] holds logged weights (yyyy-MM-dd) for at least the last 28 days.
/// [startKg] is where the goal started from (the first weigh-in, or the Coros profile
/// weight); [spark] is the 7-day average over the last 4 weeks, for Home.
GoalStatus weightStatus({
  required Goal goal,
  required DateTime today,
  required Map<String, double> weights,
  required double? currentAvg,
  double? startKg,
  List<double?> spark = const [],
}) {
  final target = goal.targetWeightKg!;
  final by = _day(goal.date!);
  final day0 = _day(today);
  if (currentAvg == null) {
    return GoalStatus(
        goal: goal, track: Track.unknown, headline: 'Target ${target.toStringAsFixed(1)} kg by ${_date(by)}', lines: ['Log your morning weight to track this.'], short: 'Log your weight to start');
  }
  final toGo = currentAvg - target;
  final daysLeft = by.difference(day0).inDays;
  final neededPerWeek = daysLeft <= 0 ? double.infinity : toGo / daysLeft * 7;
  final vis = WeightVisual(start: math.max(startKg ?? currentAvg, currentAvg), current: currentAvg, target: target, neededPerWeek: neededPerWeek, spark: spark);
  final headline = toGo <= 0
      ? '${currentAvg.toStringAsFixed(1)} kg · target reached'
      : '${currentAvg.toStringAsFixed(1)} kg · ${toGo.toStringAsFixed(1)} kg to go by ${_date(by)}';
  if (toGo <= 0) {
    return GoalStatus(goal: goal, track: Track.onTrack, headline: headline, lines: ['At or under ${target.toStringAsFixed(1)} kg (7-day average).'], short: 'Target reached', visual: vis);
  }
  final lines = <String>[];
  if (daysLeft > 0) {
    lines.add('Needs ${neededPerWeek.toStringAsFixed(2)} kg a week${neededPerWeek > 1 ? ', faster than the 0.5 to 1 kg a week usually advised' : ''}.');
  }

  // Trend: least-squares slope over the last 21 days of logged weights.
  final pts = [
    for (final e in weights.entries)
      if (!DateTime.parse(e.key).isBefore(day0.subtract(const Duration(days: 21)))) (DateTime.parse(e.key).difference(day0).inDays.toDouble(), e.value),
  ];
  final span = pts.isEmpty ? 0.0 : pts.map((p) => p.$1).reduce(math.max) - pts.map((p) => p.$1).reduce(math.min);
  if (pts.length < 3 || span < 7) {
    lines.add('Log weight on 3 or more mornings across a week to see your trend (${pts.length} so far).');
    return GoalStatus(goal: goal, track: Track.unknown, headline: headline, lines: lines, short: 'Weigh in 3 times a week for a trend', visual: vis);
  }
  final mx = pts.map((p) => p.$1).reduce((a, b) => a + b) / pts.length;
  final my = pts.map((p) => p.$2).reduce((a, b) => a + b) / pts.length;
  final slope = pts.fold(0.0, (s, p) => s + (p.$1 - mx) * (p.$2 - my)) / pts.fold(0.0, (s, p) => s + (p.$1 - mx) * (p.$1 - mx));
  final perWeek = slope * 7;
  final trend = '${perWeek <= 0 ? 'Losing' : 'Gaining'} ${perWeek.abs().toStringAsFixed(2)} kg a week over the last 3 weeks';
  Track track;
  String short;
  if (daysLeft <= 0) {
    lines.insert(0, 'The goal date has passed. Set a new one.');
    track = Track.offTrack;
    short = 'Goal date passed';
  } else if (perWeek <= -neededPerWeek * 0.9) {
    lines.insert(0, '$trend: on pace.');
    track = Track.onTrack;
    short = 'On pace: ${perWeek.abs().toStringAsFixed(1)} kg a week';
  } else if (perWeek < -0.05) {
    final reach = day0.add(Duration(days: (toGo / -slope).round()));
    lines.insert(0, '$trend: at this rate you reach ${target.toStringAsFixed(1)} kg around ${_date(reach)}${reach.year != day0.year ? ' ${reach.year}' : ''}.');
    track = Track.watch;
    short = 'At this rate: ${_date(reach)}${reach.year != day0.year ? ' ${reach.year}' : ''}';
  } else {
    lines.insert(0, '$trend.');
    track = Track.offTrack;
    short = perWeek > 0.05 ? 'Trending up' : 'Flat for 3 weeks';
  }
  return GoalStatus(goal: goal, track: track, headline: headline, lines: lines, short: short, visual: vis);
}

/// This week's runs and strength sessions against the goal (Monday to Sunday).
GoalStatus consistencyStatus({required Goal goal, required DateTime today, required int runsDone, required int strengthDone}) {
  final runs = goal.runsPerWeek ?? 0, strength = goal.strengthPerWeek ?? 0;
  final daysLeft = 8 - today.weekday; // today included
  final needRuns = math.max(0, runs - runsDone), needStrength = math.max(0, strength - strengthDone);
  final headline = 'Runs $runsDone of $runs · strength $strengthDone of $strength this week';
  final vis = ConsistencyVisual(runsDone: runsDone, runsTarget: runs, strengthDone: strengthDone, strengthTarget: strength, daysLeft: daysLeft);
  if (needRuns == 0 && needStrength == 0) {
    return GoalStatus(goal: goal, track: Track.onTrack, headline: headline, lines: ['Done for the week.'], short: 'Done for the week', visual: vis);
  }
  final track = needRuns > daysLeft || needStrength > daysLeft
      ? Track.offTrack
      : needRuns == daysLeft || needStrength == daysLeft
          ? Track.watch
          : Track.onTrack;
  final toGo = [if (needRuns > 0) '$needRuns run${needRuns == 1 ? '' : 's'}', if (needStrength > 0) '$needStrength strength'].join(' and ');
  return GoalStatus(
    goal: goal,
    track: track,
    headline: headline,
    lines: ['$toGo to go, $daysLeft day${daysLeft == 1 ? '' : 's'} left including today.'],
    short: '$toGo to go · $daysLeft day${daysLeft == 1 ? '' : 's'} left',
    visual: vis,
  );
}

/// Easy pace at the fixed HR band, oldest week first (nulls for weeks without a reading).
GoalStatus aerobicStatus({required Goal goal, required List<FitnessReading?> weeks}) {
  final r = weeks.whereType<FitnessReading>().toList();
  final vis = AerobicVisual([for (final w in weeks) w?.paceSecondsPerKm]);
  if (r.length < 3) {
    return GoalStatus(
        goal: goal,
        track: Track.unknown,
        headline: 'Pace at your easy heart rate',
        lines: ['Needs 3 weeks with easy road runs near home; ${r.length} so far.'],
        short: '${r.length} of 3 weeks of readings',
        visual: vis);
  }
  final first = (r[0].paceSecondsPerKm + r[1].paceSecondsPerKm) / 2;
  final last = (r[r.length - 1].paceSecondsPerKm + r[r.length - 2].paceSecondsPerKm) / 2;
  final change = first - last; // positive = faster
  final track = change >= 3 ? Track.onTrack : (change > -3 ? Track.watch : Track.offTrack);
  final text = change.abs() < 3 ? 'About the same as ${weeks.length} weeks ago' : '${change > 0 ? 'Faster' : 'Slower'} by ${change.abs().round()} s/km than ${weeks.length} weeks ago';
  return GoalStatus(
      goal: goal,
      track: track,
      headline: '${formatPace(r.last.paceSecondsPerKm)} /km at ${r.last.bandLow} to ${r.last.bandHigh} bpm',
      lines: ['$text.'],
      short: text,
      visual: vis);
}

/// Monday of the current week, for callers.
DateTime thisMonday(DateTime now) => mondayOf(_day(now));
