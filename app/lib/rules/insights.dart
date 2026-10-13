import '../coros/parsers.dart';
import 'planned_workout.dart';

/// Things Coros doesn't say on its own, shown on Home only when they apply (owner, 7 Oct
/// 2026). Each comes from a fixed rule over the last week or two.
enum InsightKind { hrv, sleep, restingHr, strength, tomorrow }

class Insight {
  Insight(this.kind, this.text, this.short);
  final InsightKind kind;
  final String text;

  /// A few words for Home's chips; [text] is the full sentence.
  final String short;
}

List<Insight> computeInsights({
  required DateTime today,
  required Map<CorosDate, HrvNight?> hrv, // last 7 nights
  required Map<CorosDate, SleepDay> sleep, // last 7 nights
  required int sleepMinMinutes,
  required Map<CorosDate, int?> restingHr, // last 30 days
  required List<Activity> activities, // last 14 days
  required List<PlannedWorkout> plannedStrengthLast14,
  required List<PlannedWorkout> tomorrow,
}) {
  final out = <Insight>[];
  String key(int daysAgo) => corosDate(today.subtract(Duration(days: daysAgo)));

  // HRV: nights below Coros's normal range in the last 7.
  final nights = [for (var i = 0; i < 7; i++) hrv[key(i)]].nonNulls.toList();
  final below = nights.where((n) => n.rating == HrvRating.low || n.rating == HrvRating.belowNormal).length;
  if (below >= 3) {
    out.add(Insight(InsightKind.hrv, 'HRV was below your normal range on $below of the last ${nights.length} nights. Recovery is lagging: keep easy days easy.',
        'HRV low $below of ${nights.length} nights'));
  } else if (nights.length >= 5) {
    final avg = nights.fold(0, (s, n) => s + n.avgMs) / nights.length;
    final base = nights.first.baselineMs;
    if (avg < base * 0.93) {
      out.add(Insight(InsightKind.hrv, '7-night HRV average ${avg.round()} ms is under your $base ms baseline, though each night was within range.',
          'HRV under baseline this week'));
    }
  }

  // Sleep: short main sleeps in the last 7 nights.
  final short = [for (var i = 0; i < 7; i++) sleep[key(i)]?.mainAsleepMinutes].nonNulls.where((m) => m < sleepMinMinutes).length;
  if (short >= 3) {
    out.add(Insight(InsightKind.sleep, 'Under ${sleepMinMinutes ~/ 60} hours of sleep on $short of the last 7 nights.',
        'Short sleep $short of 7 nights'));
  }

  // Resting HR: last 7 days' average against the 30 days before.
  final recent = [for (var i = 0; i < 7; i++) restingHr[key(i)]].nonNulls.toList();
  final before = [for (var i = 7; i < 37; i++) restingHr[key(i)]].nonNulls.toList();
  if (recent.length >= 4 && before.length >= 10) {
    final a = recent.reduce((x, y) => x + y) / recent.length, b = before.reduce((x, y) => x + y) / before.length;
    if (a - b >= 3) {
      out.add(Insight(InsightKind.restingHr, 'Resting HR has averaged ${a.round()} bpm this week, ${(a - b).round()} above your usual ${b.round()}.',
          'Resting HR +${(a - b).round()} bpm'));
    }
  }

  // Strength: none done in 14 days.
  final strengthDone = activities.where((a) => a.isStrength).length;
  if (strengthDone == 0) {
    out.add(Insight(InsightKind.strength,
        'No strength session in the last 14 days${plannedStrengthLast14.isEmpty ? '' : ', with ${plannedStrengthLast14.length} planned'}. It tends to slip when mileage rises.',
        'No strength in 14 days'));
  }

  // Tomorrow's long or hard session: fuel today.
  final heavy = tomorrow.where((p) => p.isRun && (p.hard || p.long)).firstOrNull;
  if (heavy != null) {
    out.add(Insight(InsightKind.tomorrow,
        'Tomorrow: ${heavy.name}${heavy.km > 0 ? ' (about ${heavy.km.round()} km)' : ''}. Keep today easy and get to bed on time.',
        'Tomorrow: ${heavy.name}'));
  }
  return out;
}
