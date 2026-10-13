import '../coros/parsers.dart';
import '../data/food_store.dart';
import '../data/goal.dart';
import '../food/food.dart';
import '../food/targets.dart';
import '../food/week_food.dart';
import '../rules/weekly_review.dart';
import 'coros_sync.dart';

/// One day on the Log screen: what was eaten and the day's targets, from stored data only.
class FoodDay {
  FoodDay({required this.date, required this.entries, required this.targets, required this.missingProfile, required this.weight});

  final DateTime date;
  final List<MealEntry> entries;

  /// Null until Coros has given height, age and sex ([missingProfile] says which).
  final FoodTargets? targets;
  final String? missingProfile;

  /// The weight logged on this day, if any.
  final double? weight;

  Nutrients get totals => Nutrients.sum(entries.map((e) => e.nutrients));
  List<MealEntry> entriesFor(Meal m) => entries.where((e) => e.meal == m).toList();
}

extension FoodDays on CorosSync {
  Future<FoodSettings> foodSettings() async {
    Future<double?> v(String key) async => double.tryParse(await db.setting(key) ?? '');
    const d = FoodSettings();
    return FoodSettings(
      carbsRest: await v(SettingKeys.carbsRest) ?? d.carbsRest,
      carbsEasy: await v(SettingKeys.carbsEasy) ?? d.carbsEasy,
      carbsHard: await v(SettingKeys.carbsHard) ?? d.carbsHard,
      protein: await v(SettingKeys.proteinGkg) ?? d.protein,
      deficitCap: await v(SettingKeys.deficitCap) ?? d.deficitCap,
    );
  }

  /// Body weight for targets: the 7-day average of logged weights, else the latest logged
  /// in the last 30 days, else the weight in the Coros profile.
  Future<double?> currentWeight(DateTime day) async {
    final logged = await db.weightsBetween(corosDate(day.subtract(const Duration(days: 30))), corosDate(day));
    return sevenDayAverage(logged, day) ?? (logged.isEmpty ? null : logged.values.last) ?? double.tryParse(await db.setting(SettingKeys.corosWeightKg) ?? '');
  }

  Future<DayTypeResult> dayTypeOn(DateTime day, {double? pace}) async {
    final key = corosDate(day);
    final planned = (await plannedBetween(day, day, pace: pace))[key] ?? const [];
    final done = await db.activitiesBetween(key, key);
    return dayTypeFor(planned: planned, done: done);
  }

  /// Active calories for [day]: Coros's figure once the day is over. For today, Coros's
  /// figure so far or your usual for this day type (last 4 weeks), whichever is higher,
  /// so the target doesn't start low and climb all day.
  Future<double> activeKcalFor(DateTime day, DayType type, DateTime now) async {
    final key = corosDate(day);
    final today = DateTime(now.year, now.month, now.day);
    final known = (await db.activeKcalBetween(key, key))[key]?.toDouble();
    if (day.isBefore(today) && known != null) return known;

    final from = day.subtract(const Duration(days: 28));
    final history = await db.activeKcalBetween(corosDate(from), corosDate(day.subtract(const Duration(days: 1))));
    final pace = await easyPace(day);
    final same = <double>[];
    for (final e in history.entries) {
      if ((await dayTypeOn(DateTime.parse(e.key), pace: pace)).type == type) same.add(e.value.toDouble());
    }
    // Your usual for this day type, from at least 3 such days; otherwise any day.
    final pool = same.length >= 3 ? same : history.values.map((v) => v.toDouble()).toList();
    final usual = pool.isEmpty ? 0.0 : (pool..sort())[pool.length ~/ 2];
    return known == null || known < usual ? usual : known;
  }

  Future<FoodDay> foodDay(DateTime day, {DateTime? now}) async {
    final d = DateTime(day.year, day.month, day.day);
    final key = corosDate(d);
    final entries = await db.entriesOn(key);
    final weightToday = (await db.weightsBetween(key, key))[key];

    final weight = await currentWeight(d);
    final height = double.tryParse(await db.setting(SettingKeys.heightCm) ?? '');
    final age = int.tryParse(await db.setting(SettingKeys.age) ?? '');
    final gender = await db.setting(SettingKeys.gender);
    final missing = [if (weight == null) 'weight', if (height == null) 'height', if (age == null) 'age', if (gender == null) 'sex'];
    if (missing.isNotEmpty) {
      return FoodDay(date: d, entries: entries, targets: null, missingProfile: missing.join(', '), weight: weightToday);
    }

    final type = await dayTypeOn(d);
    final goals = await db.goals();
    final weightGoal = goals.where((g) => g.type == GoalType.weight && g.targetWeightKg != null && g.date != null).firstOrNull;
    final targets = computeFoodTargets(
      day: d,
      body: Body(weightKg: weight!, heightCm: height!, age: age!, male: gender!.toLowerCase().startsWith('m')),
      dayType: type,
      activeKcal: await activeKcalFor(d, type.type, now ?? DateTime.now()),
      weightGoal: weightGoal == null ? null : WeightPlan(targetKg: weightGoal.targetWeightKg!, by: weightGoal.date!),
      races: [for (final g in goals) if (g.type == GoalType.race && g.date != null) g.date!],
      s: await foodSettings(),
    );
    return FoodDay(date: d, entries: entries, targets: targets, missingProfile: null, weight: weightToday);
  }

  /// The body and food part of the weekly review, from stored data.
  Future<WeekFood> weekFoodFromDatabase(DateTime monday, WeekReview review, {DateTime? asOf}) async {
    final now = asOf ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = <String, FoodDaySummary>{};
    for (var i = 0; i < 7; i++) {
      final d = monday.add(Duration(days: i));
      if (d.isAfter(today)) break;
      final day = await foodDay(d, now: now);
      if (day.entries.isNotEmpty) days[corosDate(d)] = FoodDaySummary(day.totals, day.targets);
    }
    final goal = (await db.goals()).where((g) => g.type == GoalType.weight).firstOrNull;
    return computeWeekFood(
      monday: monday,
      asOf: now,
      days: days,
      weights: await db.weightsBetween(corosDate(monday.subtract(const Duration(days: 13))), corosDate(monday.add(const Duration(days: 6)))),
      review: review,
      targetWeight: goal?.targetWeightKg,
    );
  }
}
