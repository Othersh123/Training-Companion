import '../coros/parsers.dart';
import '../rules/weekly_review.dart';
import 'food.dart';
import 'targets.dart';

/// The weekly review's body and food section (PRD F3 and F4).
class WeekFood {
  WeekFood({
    required this.weightAvg,
    required this.previousWeightAvg,
    required this.weightsLogged,
    required this.targetWeight,
    required this.daysLogged,
    required this.daysCounted,
    required this.proteinDays,
    required this.kcalDays,
    required this.underFuelling,
  });

  /// 7-day average weight at the end of the week, and the week before.
  final double? weightAvg, previousWeightAvg;
  final int weightsLogged;
  final double? targetWeight;

  /// Days with any meal logged, out of the days of the week so far.
  final int daysLogged, daysCounted;

  /// Logged days with protein at 90%+ of target, and with calories within 10% of target.
  final int proteinDays, kcalDays;

  /// Set when a heavy week lines up with low intake and worsening recovery (PRD F4).
  final String? underFuelling;
}

class FoodDaySummary {
  FoodDaySummary(this.eaten, this.targets);
  final Nutrients eaten;
  final FoodTargets? targets;
}

/// [days] holds each logged day of the week (Monday first, up to today). [weights] covers
/// the week and the week before.
WeekFood computeWeekFood({
  required DateTime monday,
  required DateTime asOf,
  required Map<String, FoodDaySummary> days,
  required Map<String, double> weights,
  required WeekReview review,
  double? targetWeight,
}) {
  final sunday = monday.add(const Duration(days: 6));
  final today = DateTime(asOf.year, asOf.month, asOf.day);
  final end = sunday.isAfter(today) ? today : sunday;
  final counted = end.difference(monday).inDays + 1;

  var protein = 0, kcal = 0, under = 0;
  for (final d in days.values) {
    final t = d.targets;
    if (t == null) continue;
    if (d.eaten.protein >= t.protein * 0.9) protein++;
    if ((d.eaten.kcal - t.kcal).abs() <= t.kcal * 0.10) kcal++;
    if (d.eaten.kcal < t.kcal * 0.85) under++;
  }

  // Under-fuelling: a heavy week (any Excessive load day, or volume more than 10% above the
  // previous 3 weeks), intake under 85% of target on 3+ logged days, and recovery slipping
  // (2+ short nights, or resting HR up 3+ bpm on the week before).
  final heavy = review.excessiveDays > 0 || (review.previousAvgKm != null && review.previousAvgKm! > 0 && review.kmRun > review.previousAvgKm! * 1.1);
  final rhrUp = review.restingHrAvg != null && review.previousRestingHrAvg != null && review.restingHrAvg! - review.previousRestingHrAvg! >= 3;
  final slipping = review.shortNights >= 2 || rhrUp;
  String? flag;
  if (heavy && under >= 3 && slipping) {
    flag = 'A heavy week, $under logged days under 85% of your calorie target, and '
        '${rhrUp ? 'resting HR up ${(review.restingHrAvg! - review.previousRestingHrAvg!).toStringAsFixed(0)} bpm' : '${review.shortNights} nights under 6 hours'}. '
        'You may be under-fuelling: eat to target on hard days, especially carbs.';
  }

  final weekEnd = sunday.isAfter(today) ? today : sunday;
  return WeekFood(
    weightAvg: sevenDayAverage(weights, weekEnd),
    previousWeightAvg: sevenDayAverage(weights, monday.subtract(const Duration(days: 1))),
    weightsLogged: weights.keys.where((d) => d.compareTo(corosDate(monday)) >= 0 && d.compareTo(corosDate(sunday)) <= 0).length,
    targetWeight: targetWeight,
    daysLogged: days.length,
    daysCounted: counted,
    proteinDays: protein,
    kcalDays: kcal,
    underFuelling: flag,
  );
}
