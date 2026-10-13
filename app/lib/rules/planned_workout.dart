/// Reads a plan workout's structure (Coros course JSON) to tell easy, long and hard sessions
/// apart and estimate their distance. Pure Dart.
library;

import 'dart:convert';

import '../coros/parsers.dart';

class PlannedWorkout {
  PlannedWorkout({
    required this.date,
    required this.name,
    required this.sport,
    required this.hard,
    required this.long,
    required this.estimatedMeters,
  });

  final CorosDate date;
  final String name;
  final WorkoutSport sport;

  /// A training section longer than a minute at Zone 3 or above (strides don't count).
  final bool hard;

  /// 16 km or more, 90 minutes or more, or named as a long run.
  final bool long;

  /// Distance targets as given; time targets converted at easy pace. Null for non-runs.
  final double? estimatedMeters;

  bool get isRun => sport == WorkoutSport.run || sport == WorkoutSport.trailRun;
  bool get isEasyRun => isRun && !hard && !long;
  double get km => (estimatedMeters ?? 0) / 1000;

  String get kindLabel => switch (sport) {
        WorkoutSport.strength => 'Strength',
        WorkoutSport.rest => 'Rest',
        WorkoutSport.cycle => 'Ride',
        _ when hard && long => 'Long, hard',
        _ when hard => 'Hard',
        _ when long => 'Long',
        _ when isRun => 'Easy',
        _ => 'Other',
      };
}

/// Zone 3 and up, or 88%+ of threshold, counts as hard when held for more than a minute.
const _hardZone = 3;
const _hardPercent = 88;
const _shortSeconds = 60;
const _shortMeters = 300;

PlannedWorkout classifyWorkout(CorosDate date, ScheduledWorkout w, {double easyPaceSecondsPerKm = 450}) {
  if (!(w.sport == WorkoutSport.run || w.sport == WorkoutSport.trailRun) || w.courseJson == null) {
    return PlannedWorkout(date: date, name: w.name, sport: w.sport, hard: false, long: false, estimatedMeters: null);
  }
  final json = jsonDecode(w.courseJson!) as Map<String, dynamic>;
  var meters = 0.0, seconds = 0.0;
  var hard = false;

  void plain(Map<String, dynamic> s, int repeats) {
    final type = s['targetType'], value = (s['targetValue'] as num?)?.toDouble() ?? 0;
    final zone = s['sectionIntensity'] as int?;
    final percent = s['intensityPercentStart'] as int?;
    final intense = (zone != null && zone >= _hardZone) || (percent != null && percent >= _hardPercent);
    final pace = intense ? easyPaceSecondsPerKm * 0.85 : easyPaceSecondsPerKm;
    final m = type == 1 ? value : (type == 2 ? value / pace * 1000 : 0.0);
    final sec = type == 2 ? value : (type == 1 ? value / 1000 * pace : 0.0);
    meters += m * repeats;
    seconds += sec * repeats;
    final sustained = (type == 2 && value > _shortSeconds) || (type == 1 && value >= _shortMeters);
    if (intense && sustained && s['sectionType'] == 2) hard = true;
  }

  for (final s in (json['sections'] as List? ?? []).cast<Map<String, dynamic>>()) {
    if (s['intervalGroup'] == true) {
      final repeats = (s['repeats'] as num?)?.toInt() ?? 1;
      for (final member in (s['sets'] as List? ?? []).cast<Map<String, dynamic>>()) {
        plain(member, repeats);
      }
    } else {
      plain(s, 1);
    }
  }
  final long = meters >= 16000 || seconds >= 90 * 60 || w.name.toLowerCase().contains('long');
  return PlannedWorkout(date: date, name: w.name, sport: w.sport, hard: hard, long: long, estimatedMeters: meters);
}

/// Whether the plan says [date]'s run was meant to be easy: true for an easy run, false for a
/// long or hard one, null when the plan has no run that day (fall back to the duration rule).
bool? isPlannedEasyDay(CorosDate date, List<ScheduledWorkout>? planned) {
  final runs = [
    for (final w in planned ?? const <ScheduledWorkout>[])
      if (w.sport == WorkoutSport.run || w.sport == WorkoutSport.trailRun) classifyWorkout(date, w),
  ];
  if (runs.isEmpty) return null;
  return runs.every((r) => r.isEasyRun);
}
