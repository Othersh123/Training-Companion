/// A goal (PRD F2): race, body weight, consistency or aerobic fitness. Several can be active;
/// one is primary.
library;

enum GoalType { race, weight, consistency, aerobic }

enum Terrain { road, trail }

class Goal {
  Goal({
    this.id,
    required this.type,
    required this.name,
    this.date,
    this.distanceMeters,
    this.terrain = Terrain.road,
    this.targetSeconds,
    this.targetWeightKg,
    this.runsPerWeek,
    this.strengthPerWeek,
    this.primary = false,
  });

  final int? id;
  final GoalType type;
  final String name;

  /// Race day, or the date a weight goal is due. Null for open-ended goals.
  final DateTime? date;
  final int? distanceMeters;
  final Terrain terrain;

  /// Optional race target; with none, the goal is to finish.
  final int? targetSeconds;
  final double? targetWeightKg;
  final int? runsPerWeek;
  final int? strengthPerWeek;
  final bool primary;

  Map<String, Object?> toRow() => {
        'id': id,
        'type': type.name,
        'name': name,
        'date': date?.toIso8601String().substring(0, 10),
        'distance_m': distanceMeters,
        'terrain': terrain.name,
        'target_s': targetSeconds,
        'target_weight': targetWeightKg,
        'runs_per_week': runsPerWeek,
        'strength_per_week': strengthPerWeek,
        'is_primary': primary ? 1 : 0,
      };

  static Goal fromRow(Map<String, Object?> r) => Goal(
        id: r['id'] as int?,
        type: GoalType.values.byName(r['type'] as String),
        name: r['name'] as String,
        date: r['date'] == null ? null : DateTime.parse(r['date'] as String),
        distanceMeters: r['distance_m'] as int?,
        terrain: Terrain.values.byName(r['terrain'] as String? ?? 'road'),
        targetSeconds: r['target_s'] as int?,
        targetWeightKg: (r['target_weight'] as num?)?.toDouble(),
        runsPerWeek: r['runs_per_week'] as int?,
        strengthPerWeek: r['strength_per_week'] as int?,
        primary: r['is_primary'] == 1,
      );

  /// Days from [today] to race day; negative once it's passed.
  int? daysTo(DateTime today) => date?.difference(DateTime(today.year, today.month, today.day)).inDays;

  String get summary => switch (type) {
        GoalType.race => [
            if (distanceMeters != null) '${(distanceMeters! / 1000).toStringAsFixed(distanceMeters! % 1000 == 0 ? 0 : 1)} km',
            terrain == Terrain.trail ? 'trail' : 'road',
            targetSeconds == null ? 'to finish' : 'target ${formatDuration(targetSeconds!)}',
          ].join(' · '),
        GoalType.weight => 'Reach ${targetWeightKg?.toStringAsFixed(1)} kg',
        GoalType.consistency => '${runsPerWeek ?? 0} runs and ${strengthPerWeek ?? 0} strength sessions a week',
        GoalType.aerobic => 'Faster pace at your easy heart rate',
      };
}

String formatDuration(int seconds) {
  final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60, s = seconds % 60;
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}' : '$m:${s.toString().padLeft(2, '0')}';
}
