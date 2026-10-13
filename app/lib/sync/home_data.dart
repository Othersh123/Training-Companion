import '../coros/parsers.dart';
import '../data/food_store.dart';
import '../data/goal.dart';
import '../food/targets.dart' show sevenDayAverage;
import '../rules/goal_status.dart';
import '../rules/insights.dart';
import '../rules/weekly_review.dart';
import 'coros_sync.dart';

/// This week so far, in one strip on Home.
class WeekStrip {
  WeekStrip({
    required this.kmDone,
    required this.kmPlanned,
    required this.runsDone,
    required this.runsPlanned,
    required this.strengthDone,
    required this.strengthPlanned,
    required this.easyUnder,
    required this.easyRuns,
    required this.longAhead,
    required this.flag,
  });

  final double kmDone, kmPlanned;
  final int runsDone, runsPlanned, strengthDone, strengthPlanned, easyUnder, easyRuns;

  /// "15k Long Run on Sun", when this week's long run is still to come.
  final String? longAhead;

  /// One drift flag, if any: Excessive load days, or the weekly volume jump.
  final String? flag;
}

class HomeData {
  HomeData({required this.goals, required this.week, required this.insights});
  final List<GoalStatus> goals;
  final WeekStrip week;
  final List<Insight> insights;
}

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

extension HomeLoad on CorosSync {
  Future<HomeData> homeData(DateTime now) async {
    final today = DateTime(now.year, now.month, now.day);
    final monday = mondayOf(today);
    final sunday = monday.add(const Duration(days: 6));
    final goals = await db.goals();
    final review = await weekReviewFromDatabase(monday, asOf: now);
    final pace = await easyPace(today);

    // Goals, primary first (db.goals() orders them).
    final race = goals.where((g) => g.type == GoalType.race && g.date != null).firstOrNull;
    final horizon = race != null && race.date!.isAfter(today) ? race.date! : today.add(const Duration(days: 56));
    final planned = await plannedBetween(today.subtract(const Duration(days: 14)), horizon, pace: pace);
    final runs = await db.activitiesBetween(corosDate(today.subtract(const Duration(days: 16 * 7))), corosDate(today));
    final weights = await db.weightsBetween(corosDate(today.subtract(const Duration(days: 35))), corosDate(today));
    // The block starts where the Coros plan does, if there is one.
    DateTime? blockStart;
    final planId = (await db.scheduleBetween(corosDate(today.subtract(const Duration(days: 120))), corosDate(horizon)))
        .values
        .expand((d) => d)
        .map((w) => w.planId)
        .nonNulls
        .firstOrNull;
    if (planId != null) blockStart = DateTime.tryParse((await db.planInfo(planId))?.$2 ?? '');
    // Weight progress starts from the Coros profile weight, else the first weigh-in.
    final firstLogged = (await db.weightsBetween('2000-01-01', corosDate(today))).values.firstOrNull;
    final startKg = double.tryParse(await db.setting(SettingKeys.corosWeightKg) ?? '') ?? firstLogged;
    final spark = [for (var i = 27; i >= 0; i--) sevenDayAverage(weights, today.subtract(Duration(days: i)))];
    final statuses = <GoalStatus>[];
    for (final g in goals) {
      switch (g.type) {
        case GoalType.race when g.date != null:
          statuses.add(raceStatus(goal: g, today: now, planned: planned, runs: runs, guard: g == race ? await guardFromDatabase(now) : null, blockStart: blockStart));
        case GoalType.weight when g.date != null && g.targetWeightKg != null:
          statuses.add(weightStatus(goal: g, today: now, weights: weights, currentAvg: sevenDayAverage(weights, today), startKg: startKg, spark: spark));
        case GoalType.consistency:
          statuses.add(consistencyStatus(goal: g, today: now, runsDone: review.runsDone, strengthDone: review.strengthDone));
        case GoalType.aerobic:
          final readings = [
            for (var w = 5; w >= 0; w--) (await weekReviewFromDatabase(monday.subtract(Duration(days: 7 * w)), asOf: now)).fitness,
          ];
          statuses.add(aerobicStatus(goal: g, weeks: readings));
        default:
          break;
      }
    }

    // This week so far.
    final weekPlan = [for (final e in planned.entries) if (e.key.compareTo(corosDate(monday)) >= 0 && e.key.compareTo(corosDate(sunday)) <= 0) ...e.value];
    final longAhead = [
      for (final e in planned.entries)
        if (e.key.compareTo(corosDate(today)) >= 0 && e.key.compareTo(corosDate(sunday)) <= 0)
          for (final p in e.value)
            if (p.isRun && p.long) '${p.name} on ${_days[DateTime.parse(e.key).weekday - 1]}',
    ].firstOrNull;
    final avg = review.previousAvgKm;
    final week = WeekStrip(
      kmDone: review.kmRun,
      kmPlanned: weekPlan.where((p) => p.isRun).fold(0.0, (s, p) => s + p.km),
      runsDone: review.runsDone,
      runsPlanned: review.runsPlanned ?? weekPlan.where((p) => p.isRun).length,
      strengthDone: review.strengthDone,
      strengthPlanned: review.strengthPlanned,
      easyUnder: review.easyUnderCap,
      easyRuns: review.easyRuns,
      longAhead: longAhead,
      flag: review.excessiveDays > 0
          ? 'Load Excessive on ${review.excessiveDays} day${review.excessiveDays == 1 ? '' : 's'} this week'
          : avg != null && avg > 0 && review.kmRun > avg * 1.1
              ? 'Already ${((review.kmRun / avg - 1) * 100).round()}% above your 3-week average'
              : null,
    );

    // Insights.
    final t = await thresholds();
    final insights = computeInsights(
      today: today,
      hrv: await db.hrvBetween(corosDate(today.subtract(const Duration(days: 6))), corosDate(today)),
      sleep: await db.sleepBetween(corosDate(today.subtract(const Duration(days: 6))), corosDate(today)),
      sleepMinMinutes: t.sleepMinMinutes,
      restingHr: await db.restingHrBetween(corosDate(today.subtract(const Duration(days: 37))), corosDate(today)),
      activities: runs.where((a) => !a.start.isBefore(today.subtract(const Duration(days: 14)))).toList(),
      plannedStrengthLast14: [
        for (final e in planned.entries)
          if (e.key.compareTo(corosDate(today)) < 0) ...e.value.where((p) => p.sport == WorkoutSport.strength),
      ],
      tomorrow: planned[corosDate(today.add(const Duration(days: 1)))] ?? const [],
    );
    return HomeData(goals: statuses, week: week, insights: insights);
  }
}
