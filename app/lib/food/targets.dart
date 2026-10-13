import 'dart:math' as math;

import '../coros/parsers.dart';
import '../rules/planned_workout.dart';

/// PRD, Food targets by day type. Every number here is an estimate and is labelled so on screen.
enum DayType { rest, easy, hard }

extension DayTypeLabel on DayType {
  String get label => switch (this) {
        DayType.rest => 'Rest day',
        DayType.easy => 'Easy day',
        DayType.hard => 'Hard or long day',
      };
}

class FoodSettings {
  const FoodSettings({
    this.carbsRest = 3,
    this.carbsEasy = 5,
    this.carbsHard = 7,
    this.protein = 1.6,
    this.fatMinShare = 0.20,
    this.deficitCap = 500,
    this.carbsFloor = 3,
    this.fibrePer1000 = 14,
  });

  /// Fibre target in grams per 1,000 kcal (owner asked for a fibre card, 7 Oct 2026).
  final double fibrePer1000;

  /// On weight-goal deficit days carbs may drop to fit calories, but not below this (g/kg).
  final double carbsFloor;

  /// Carbs in g per kg body weight by day type, protein in g/kg every day. Inside the 2016
  /// ACSM / Academy / Dietitians of Canada ranges (PRD).
  final double carbsRest, carbsEasy, carbsHard, protein;

  /// Fat never below this share of the day's calories.
  final double fatMinShare;

  /// The most a weight goal takes off a day, in kcal. A proposed default with no source (PRD).
  final double deficitCap;

  double carbsFor(DayType t) => switch (t) {
        DayType.rest => carbsRest,
        DayType.easy => carbsEasy,
        DayType.hard => carbsHard,
      };
}

class DayTypeResult {
  DayTypeResult(this.type, this.reason);
  final DayType type;

  /// "Threshold Workout planned", "Ran 95 min", "Nothing planned or done".
  final String reason;
}

/// Day type from the plan, or from Coros when a workout was done without a plan (PRD F4).
/// The heavier of the two wins: a planned easy day that became a 2-hour run is a hard day.
DayTypeResult dayTypeFor({required List<PlannedWorkout> planned, required List<Activity> done}) {
  final heavyPlan = planned.where((p) => p.hard || p.long).firstOrNull;
  if (heavyPlan != null) {
    return DayTypeResult(DayType.hard, '${heavyPlan.name} planned (${heavyPlan.hard ? 'hard session' : 'long: 16 km or 90 minutes or more'})');
  }
  final longDone = done.where((a) => a.durationSeconds >= 90 * 60).firstOrNull;
  if (longDone != null) return DayTypeResult(DayType.hard, '${longDone.name}, ${longDone.durationSeconds ~/ 60} min');
  final easyPlan = planned.where((p) => p.sport != WorkoutSport.rest).firstOrNull;
  if (easyPlan != null) return DayTypeResult(DayType.easy, '${easyPlan.name} planned');
  final anyDone = done.where((a) => a.durationSeconds >= 20 * 60).firstOrNull;
  if (anyDone != null) return DayTypeResult(DayType.easy, '${anyDone.name}, ${anyDone.durationSeconds ~/ 60} min');
  return DayTypeResult(DayType.rest, 'Nothing planned or done');
}

class Body {
  Body({required this.weightKg, required this.heightCm, required this.age, required this.male});
  final double weightKg;
  final double heightCm;
  final int age;
  final bool male;

  /// Mifflin-St Jeor resting energy, kcal a day.
  double get restingKcal => 10 * weightKg + 6.25 * heightCm - 5 * age + (male ? 5 : -161);
}

class WeightPlan {
  WeightPlan({required this.targetKg, required this.by});
  final double targetKg;
  final DateTime by;
}

class FoodTargets {
  FoodTargets({
    required this.kcal,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.fibre,
    required this.dayType,
    required this.restingKcal,
    required this.activeKcal,
    required this.deficit,
    required this.deficitNote,
  });

  final double kcal, protein, carbs, fat;

  /// 14 g per 1,000 kcal of the day's target (US Institute of Medicine adequate intake).
  final double fibre;
  final DayTypeResult dayType;
  final double restingKcal;
  final double activeKcal;

  /// kcal taken off for a weight goal today (0 when paused or none).
  final double deficit;

  /// Why the deficit is what it is, or null without a weight goal.
  final String? deficitNote;
}

/// The day's targets. [activeKcal] is Coros active calories (the estimate for a day still
/// under way). [races] are race-goal dates: no deficit from 14 days before to 7 days after.
FoodTargets computeFoodTargets({
  required DateTime day,
  required Body body,
  required DayTypeResult dayType,
  required double activeKcal,
  WeightPlan? weightGoal,
  List<DateTime> races = const [],
  FoodSettings s = const FoodSettings(),
}) {
  final d = DateTime(day.year, day.month, day.day);
  final resting = body.restingKcal;

  // Weight goal: spread the remaining loss to the date, capped, and never on hard days or
  // around a race (owner, 5 Oct 2026).
  var deficit = 0.0;
  String? note;
  if (weightGoal != null) {
    final daysLeft = DateTime(weightGoal.by.year, weightGoal.by.month, weightGoal.by.day).difference(d).inDays;
    final toLose = body.weightKg - weightGoal.targetKg;
    final race = races.where((r) {
      final days = d.difference(DateTime(r.year, r.month, r.day)).inDays;
      return days >= -14 && days <= 7;
    }).firstOrNull;
    if (toLose <= 0) {
      note = 'At or under your target weight: no deficit.';
    } else if (daysLeft <= 0) {
      note = 'Your weight goal date has passed: no deficit until you set a new date.';
    } else if (dayType.type == DayType.hard) {
      note = 'No deficit on hard or long days, so training is fully fuelled.';
    } else if (race != null) {
      note = 'No deficit from 2 weeks before a race to 1 week after.';
    } else {
      final needed = toLose * 7700 / daysLeft;
      deficit = math.min(s.deficitCap, needed);
      note = deficit < needed
          ? '${deficit.round()} kcal deficit for your weight goal (capped; ${needed.round()} a day would be needed to reach it on time).'
          : '${deficit.round()} kcal deficit for your weight goal.';
    }
  }

  final protein = s.protein * body.weightKg;
  var carbs = s.carbsFor(dayType.type) * body.weightKg;
  var kcal = resting + activeKcal - deficit;
  var carbsCut = false;
  if (deficit > 0) {
    // Calories win on deficit days (owner, 5 Oct 2026): carbs shrink to fit the calorie target
    // with fat at its minimum share, but never below the floor. Hard days never get here.
    final fits = (kcal * (1 - s.fatMinShare) - protein * 4) / 4;
    final floor = s.carbsFloor * body.weightKg;
    if (fits < carbs) {
      carbs = math.max(fits, math.min(floor, carbs));
      carbsCut = true;
    }
  }
  var fatKcal = kcal - protein * 4 - carbs * 4;
  if (fatKcal < kcal * s.fatMinShare) {
    // Protein and carbs leave too little room for fat: raise calories so fat is its minimum share.
    kcal = (protein * 4 + carbs * 4) / (1 - s.fatMinShare);
    fatKcal = kcal * s.fatMinShare;
  }
  // The fat floor can eat into the deficit; report what actually applies.
  final applied = math.max(0.0, resting + activeKcal - kcal);
  if (deficit > 0 && applied < deficit - 1) {
    note = '${applied.round()} kcal deficit for your weight goal (${deficit.round()} planned; carbs are at their ${s.carbsFloor.toStringAsFixed(0)} g/kg floor).';
    deficit = applied;
  } else if (carbsCut && deficit > 0) {
    note = '$note Carbs are lowered to ${(carbs / body.weightKg).toStringAsFixed(1)} g/kg to make room for it.';
  }
  return FoodTargets(
    kcal: kcal,
    protein: protein,
    carbs: carbs,
    fat: fatKcal / 9,
    fibre: kcal / 1000 * s.fibrePer1000,
    dayType: dayType,
    restingKcal: resting,
    activeKcal: activeKcal,
    deficit: deficit,
    deficitNote: note,
  );
}

/// The 7-day average of logged weights ending on [day] (PRD: the trend uses a 7-day average).
double? sevenDayAverage(Map<String, double> weights, DateTime day) {
  final values = [
    for (var i = 0; i < 7; i++) weights[corosDate(day.subtract(Duration(days: i)))],
  ].nonNulls.toList();
  return values.isEmpty ? null : values.reduce((a, b) => a + b) / values.length;
}
