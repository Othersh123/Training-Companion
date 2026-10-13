/// Strict parsers for COROS MCP replies.
///
/// Coros returns prose written for AI assistants, with no version and no structured
/// alternative (learnings L5, L13). Every parser checks the shape it expects and throws
/// [CorosFormatException] on anything else, so a wording change surfaces as an error
/// and is never mistaken for a day without data.
library;

import 'dart:convert';

class CorosFormatException implements Exception {
  CorosFormatException(this.tool, this.message);

  final String tool;
  final String message;

  @override
  String toString() => 'Coros format changed in $tool: $message';
}

/// A calendar day as Coros writes it (wake-up day for sleep and HRV).
typedef CorosDate = String; // yyyy-MM-dd

final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

String _compactToIso(String yyyymmdd) =>
    '${yyyymmdd.substring(0, 4)}-${yyyymmdd.substring(4, 6)}-${yyyymmdd.substring(6, 8)}';

void _expectHeader(String tool, String text, String prefix) {
  if (!text.trimLeft().startsWith(prefix)) {
    throw CorosFormatException(tool, 'reply does not start with "$prefix"');
  }
}

List<String> _lines(String text) => text.replaceAll('\r\n', '\n').split('\n');

/// Parses Coros durations: `6h 53min`, `50min`, `55 min`, `0 min`, `1h 0min`, `7h`.
int parseMinutes(String tool, String raw) {
  final m = RegExp(r'^(?:(\d+)h)?\s*(?:(\d+)\s*min)?$').firstMatch(raw.trim());
  if (m == null || (m.group(1) == null && m.group(2) == null)) {
    throw CorosFormatException(tool, 'unreadable duration "$raw"');
  }
  return int.parse(m.group(1) ?? '0') * 60 + int.parse(m.group(2) ?? '0');
}

/// Parses clock durations: `37:12` (m:ss) or `2:28:59` (h:mm:ss), to seconds.
int parseClockSeconds(String tool, String raw) {
  final parts = raw.trim().split(':');
  if (parts.length < 2 || parts.length > 3 || parts.any((p) => int.tryParse(p) == null)) {
    throw CorosFormatException(tool, 'unreadable clock time "$raw"');
  }
  return parts.map(int.parse).fold(0, (acc, p) => acc * 60 + p);
}

// ---------------------------------------------------------------------------
// querySleepHrv

/// Coros's own rating. `low` is a further step below `belowNormal` (seen on older nights).
enum HrvRating { low, belowNormal, normal, aboveNormal }

class HrvNight {
  HrvNight({required this.avgMs, required this.rating, required this.rangeLowMs, required this.rangeHighMs, required this.baselineMs});

  final int avgMs;
  final HrvRating rating;
  final int rangeLowMs;
  final int rangeHighMs;
  final int baselineMs;
}

/// Result per wake-up day. A day maps to null when Coros says "No data" for it;
/// days Coros leaves out of the assessment are absent from the map (also no data).
Map<CorosDate, HrvNight?> parseSleepHrv(String text) {
  const tool = 'querySleepHrv';
  _expectHeader(tool, text, 'Sleep HRV');
  final lines = _lines(text);
  final start = lines.indexWhere((l) => l.startsWith('HRV Assessment'));
  if (start < 0) throw CorosFormatException(tool, 'no "HRV Assessment" section');
  // With no nights at all, Coros replaces the time series section with "No sleep HRV time series data found…" (4 Oct 2026).
  final end = lines.indexWhere((l) => l.startsWith('Sleep HRV Time Series') || l.startsWith('No sleep HRV time series data found'), start);
  final section = lines.sublist(start + 1, end < 0 ? lines.length : end).where((l) => l.trim().isNotEmpty && !l.startsWith('===')).toList();

  final result = <CorosDate, HrvNight?>{};
  var i = 0;
  while (i < section.length) {
    final header = RegExp(r'^(\d{4}-\d{2}-\d{2}):$').firstMatch(section[i].trim());
    if (header == null) throw CorosFormatException(tool, 'expected a date line, got "${section[i].trim()}"');
    final date = header.group(1)!;
    if (i + 1 < section.length && section[i + 1].trim() == 'No data') {
      result[date] = null;
      i += 2;
      continue;
    }
    if (i + 3 >= section.length) throw CorosFormatException(tool, 'incomplete assessment for $date');
    final avg = RegExp(r'^HRV Avg: (\d+) ms — (.+)$').firstMatch(section[i + 1].trim());
    final range = RegExp(r'^Normal Range: (\d+) - (\d+) ms$').firstMatch(section[i + 2].trim());
    final baseline = RegExp(r'^Baseline: (\d+) ms$').firstMatch(section[i + 3].trim());
    if (avg == null || range == null || baseline == null) {
      throw CorosFormatException(tool, 'unexpected assessment lines for $date');
    }
    final rating = switch (avg.group(2)!.trim()) {
      'Low' => HrvRating.low,
      'Below normal' => HrvRating.belowNormal,
      'Normal' => HrvRating.normal,
      'Above normal' => HrvRating.aboveNormal,
      final other => throw CorosFormatException(tool, 'unknown HRV rating "$other" for $date'),
    };
    result[date] = HrvNight(
      avgMs: int.parse(avg.group(1)!),
      rating: rating,
      rangeLowMs: int.parse(range.group(1)!),
      rangeHighMs: int.parse(range.group(2)!),
      baselineMs: int.parse(baseline.group(1)!),
    );
    i += 4;
  }
  return result;
}

// ---------------------------------------------------------------------------
// queryRestingHeartRate

/// Resting HR per day; null where Coros says "No data".
Map<CorosDate, int?> parseRestingHr(String text) {
  const tool = 'queryRestingHeartRate';
  _expectHeader(tool, text, 'Resting Heart Rate');
  final result = <CorosDate, int?>{};
  for (final raw in _lines(text).skip(1)) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('===')) continue;
    final m = RegExp(r'^(\d{4}-\d{2}-\d{2}): (?:(\d+) bpm|(No data))$').firstMatch(line);
    if (m == null) throw CorosFormatException(tool, 'unexpected line "$line"');
    result[m.group(1)!] = m.group(2) == null ? null : int.parse(m.group(2)!);
  }
  return result;
}

// ---------------------------------------------------------------------------
// queryTrainingLoadAssessment

class LoadDay {
  LoadDay({required this.label, required this.shortTerm, required this.longTerm, required this.ratio});

  /// Coros's own label, used as given (for example Optimized, Excessive).
  final String label;
  final int shortTerm;
  final int longTerm;
  final double ratio;
}

Map<CorosDate, LoadDay> parseTrainingLoad(String text) {
  const tool = 'queryTrainingLoadAssessment';
  _expectHeader(tool, text, 'Training Load Assessment');
  final lines = _lines(text).map((l) => l.trim()).where((l) => l.isNotEmpty && !l.startsWith('===')).skip(1).toList();
  final result = <CorosDate, LoadDay>{};
  if (lines.length % 5 != 0) throw CorosFormatException(tool, 'expected 5 lines per day, got ${lines.length} lines');
  for (var i = 0; i < lines.length; i += 5) {
    if (!_isoDate.hasMatch(lines[i])) throw CorosFormatException(tool, 'expected a date, got "${lines[i]}"');
    final label = RegExp(r'^Comment: (.+)$').firstMatch(lines[i + 1]);
    final st = RegExp(r'^Short-Term Load: (\d+)$').firstMatch(lines[i + 2]);
    final lt = RegExp(r'^Long-Term Load: (\d+)$').firstMatch(lines[i + 3]);
    final ratio = RegExp(r'^Load Ratio: (\d+(?:\.\d+)?)$').firstMatch(lines[i + 4]);
    if (label == null || st == null || lt == null || ratio == null) {
      throw CorosFormatException(tool, 'unexpected lines for ${lines[i]}');
    }
    result[lines[i]] = LoadDay(
      label: label.group(1)!.trim(),
      shortTerm: int.parse(st.group(1)!),
      longTerm: int.parse(lt.group(1)!),
      ratio: double.parse(ratio.group(1)!),
    );
  }
  return result;
}

// ---------------------------------------------------------------------------
// querySleepOverview

class SleepDay {
  SleepDay({this.mainAsleepMinutes, this.mainPeriodMinutes, this.mainWindow, required this.napMinutes});

  /// Null when there was no main (night) sleep, for example the watch wasn't worn.
  final int? mainAsleepMinutes;
  final int? mainPeriodMinutes;
  final String? mainWindow;
  final int napMinutes;
}

Map<CorosDate, SleepDay> parseSleepOverview(String text) {
  const tool = 'querySleepOverview';
  _expectHeader(tool, text, 'Sleep Overview');
  final result = <CorosDate, SleepDay>{};
  String? date;
  Map<String, String> fields = {};

  var notAvailable = false;

  void flush() {
    if (date == null) return;
    // "Sleep Score: 0" then "Sleep detail for this day is not available yet." means no data.
    if (notAvailable) {
      if (fields.keys.any((k) => k != 'Sleep Score')) throw CorosFormatException(tool, 'sleep data on an unavailable day $date');
      result[date] = SleepDay(napMinutes: 0);
      return;
    }
    // Daily Sleep is absent on some nights (scope "main sleep", e.g. 26 Jul 2026); the app doesn't use it.
    if (!fields.containsKey('Sleep Score')) throw CorosFormatException(tool, 'no "Sleep Score" for $date');
    final asleep = fields['Main Sleep (asleep)'];
    final period = fields['Main Sleep Period (incl. awake)'];
    if ((asleep == null) != (period == null)) throw CorosFormatException(tool, 'partial main sleep for $date');
    int? asleepMin = asleep == null ? null : parseMinutes(tool, asleep);
    int? periodMin = period == null ? null : parseMinutes(tool, period);
    // Older nights (before mid-July 2026) give one "Main Sleep" figure: time in bed.
    // Time asleep is that minus "Awake Time", which reconciles with Daily Sleep.
    final legacy = fields['Main Sleep'];
    if (asleepMin == null && legacy != null) {
      final awake = fields['Awake Time'];
      if (awake == null) throw CorosFormatException(tool, 'legacy main sleep without awake time for $date');
      periodMin = parseMinutes(tool, legacy);
      asleepMin = periodMin - parseMinutes(tool, awake);
    }
    final naps = fields['Naps Total'] ?? fields['Naps Total (asleep)'];
    if (naps == null) throw CorosFormatException(tool, 'no naps total for $date');
    result[date] = SleepDay(
      mainAsleepMinutes: asleepMin,
      mainPeriodMinutes: periodMin,
      mainWindow: fields['Main Sleep Window'],
      // Legacy naps carry a note: "21 min (includes legacy reported durations)".
      napMinutes: parseMinutes(tool, naps.replaceAll(RegExp(r'\s*\(includes legacy[^)]*\)$'), '')),
    );
  }

  for (final raw in _lines(text).skip(1)) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('===') || line.startsWith('Note:')) continue;
    if (_isoDate.hasMatch(line)) {
      flush();
      date = line;
      fields = {};
      notAvailable = false;
      continue;
    }
    if (line == 'Sleep detail for this day is not available yet.') {
      notAvailable = true;
      continue;
    }
    final kv = RegExp(r'^([^:]+): (.+)$').firstMatch(line);
    if (kv == null || date == null) throw CorosFormatException(tool, 'unexpected line "$line"');
    fields[kv.group(1)!.trim()] = kv.group(2)!.replaceAll('(incl. naps)', '').trim();
  }
  flush();
  return result;
}

// ---------------------------------------------------------------------------
// querySportRecords

/// Coros sport code for strength sessions.
const strengthSportType = 402;

class Activity {
  Activity({
    required this.labelId,
    required this.sportType,
    required this.name,
    required this.date,
    required this.start,
    required this.end,
    required this.durationSeconds,
    this.distanceMeters,
    this.avgHr,
    this.location,
    this.startLat,
    this.startLon,
  });

  final String labelId;
  final int sportType;
  final String name;
  final CorosDate date;
  final DateTime start;
  final DateTime end;
  final int durationSeconds;
  final int? distanceMeters;
  final int? avgHr;
  final String? location;
  final double? startLat;
  final double? startLon;

  /// Coros codes 100 to 103: outdoor, indoor, trail and track running.
  bool get isRun => sportType >= 100 && sportType <= 103;

  bool get isStrength => sportType == strengthSportType;

  /// Outdoor road running only (not indoor, trail or track).
  bool get isRoadRun => sportType == 100;
}

List<Activity> parseSportRecords(String text) {
  const tool = 'querySportRecords';
  // An empty range is one line instead of the header (7 Oct 2026, history before 2025).
  if (RegExp(r'^No sport records found from \d{4}-\d{2}-\d{2} to \d{4}-\d{2}-\d{2}\.$').hasMatch(text.trim())) return [];
  _expectHeader(tool, text, 'Sport Records');
  final count = RegExp(r'\((\d+) records?\)').firstMatch(text.split('\n').first);
  if (count == null) throw CorosFormatException(tool, 'no record count in header');
  final expected = int.parse(count.group(1)!);

  // Strength and gym records break a line before "| Avg HR" (seen 2 Oct 2026); rejoin it.
  final normalised = text.replaceAll('\r\n', '\n').replaceAll(RegExp(r'\n\s*\|'), ' |');
  final blocks = RegExp(r'^\d+\. (.+?) — (\d{4}-\d{2}-\d{2})\n((?:[ \t]+.+\n?)+)', multiLine: true).allMatches(normalised).toList();
  if (blocks.length != expected) throw CorosFormatException(tool, 'header says $expected records, found ${blocks.length}');

  return blocks.map((b) {
    final body = b.group(3)!;
    String? field(String key) => RegExp('(?:^|\\|)\\s*${RegExp.escape(key)}: ([^|\\n]+)', multiLine: true).firstMatch(body)?.group(1)?.trim();
    String need(String key) => field(key) ?? (throw CorosFormatException(tool, 'record "${b.group(1)}" on ${b.group(2)} has no $key'));

    final window = RegExp(r'startTimestamp=(\d+) \| endTimestamp=(\d+)').firstMatch(body);
    if (window == null) throw CorosFormatException(tool, 'record on ${b.group(2)} has no time window');
    final ids = RegExp(r'LabelId: (\d+) \| SportType: (\d+)').firstMatch(body);
    if (ids == null) throw CorosFormatException(tool, 'record on ${b.group(2)} has no LabelId/SportType');

    final distance = field('Distance');
    int? meters;
    if (distance != null) {
      final d = RegExp(r'^(\d+(?:\.\d+)?) (km|m)$').firstMatch(distance);
      if (d == null) throw CorosFormatException(tool, 'unreadable distance "$distance"');
      final v = double.parse(d.group(1)!);
      meters = (d.group(2) == 'km' ? v * 1000 : v).round();
    }
    final hr = field('Avg HR');
    int? avgHr;
    if (hr != null) {
      final h = RegExp(r'^(\d+) bpm$').firstMatch(hr);
      if (h == null) throw CorosFormatException(tool, 'unreadable Avg HR "$hr"');
      avgHr = int.parse(h.group(1)!);
    }
    double? lat, lon;
    final coords = field('Start Coordinates');
    if (coords != null) {
      final c = RegExp(r'^(-?\d+\.\d+), (-?\d+\.\d+)$').firstMatch(coords);
      if (c == null) throw CorosFormatException(tool, 'unreadable coordinates "$coords"');
      lat = double.parse(c.group(1)!);
      lon = double.parse(c.group(2)!);
    }

    return Activity(
      labelId: ids.group(1)!,
      sportType: int.parse(ids.group(2)!),
      name: b.group(1)!.trim(),
      date: b.group(2)!,
      start: DateTime.fromMillisecondsSinceEpoch(int.parse(window.group(1)!) * 1000, isUtc: true),
      end: DateTime.fromMillisecondsSinceEpoch(int.parse(window.group(2)!) * 1000, isUtc: true),
      durationSeconds: parseClockSeconds(tool, need('Duration')),
      distanceMeters: meters,
      avgHr: avgHr,
      location: field('Location'),
      startLat: lat,
      startLon: lon,
    );
  }).toList();
}

// ---------------------------------------------------------------------------
// queryTrainingSchedule

enum WorkoutSport { run, trailRun, cycle, strength, rest, unknown }

class ScheduledWorkout {
  ScheduledWorkout({
    required this.name,
    this.distanceMeters,
    this.estimatedSeconds,
    this.trainingLoad,
    this.planId,
    this.sport = WorkoutSport.unknown,
    this.courseJson,
  });

  /// For plan workouts the schedule gives a code (S5724); [CorosSync] swaps in the real
  /// name from the plan details (L28).
  final String name;
  final int? distanceMeters;
  final int? estimatedSeconds;
  final int? trainingLoad;

  /// Internal link to the Coros plan; never shown to the user.
  final String? planId;
  final WorkoutSport sport;

  /// The workout's structure from the plan (sections, zones), as Coros sends it.
  final String? courseJson;

  ScheduledWorkout withPlanCourse(PlanCourse c) => ScheduledWorkout(
        name: c.name,
        distanceMeters: distanceMeters,
        estimatedSeconds: estimatedSeconds,
        trainingLoad: trainingLoad,
        planId: planId,
        sport: c.sport,
        courseJson: c.courseJson,
      );
}

/// Workouts per date. Plan IDs are kept internally to look up real names (L28).
Map<CorosDate, List<ScheduledWorkout>> parseTrainingSchedule(String text) {
  const tool = 'queryTrainingSchedule';
  // A rest day (or empty range) gets this one line instead of the usual header (5 Oct 2026).
  if (text.trim() == 'No training schedule found.') return {};
  _expectHeader(tool, text, 'Training Schedule');
  final result = <CorosDate, List<ScheduledWorkout>>{};
  final blocks = text.replaceAll('\r\n', '\n').split(RegExp(r'\n\s*\n'));
  for (final block in blocks) {
    final lines = block.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    if (lines.isEmpty || !_isoDate.hasMatch(lines.first)) continue; // header and the closing note
    if (lines.length < 2) throw CorosFormatException(tool, 'workout on ${lines.first} has no name');
    final fields = <String, String>{};
    for (final l in lines.skip(2)) {
      final kv = RegExp(r'^([^:]+): (.+)$').firstMatch(l);
      if (kv == null) throw CorosFormatException(tool, 'unexpected line "$l" on ${lines.first}');
      fields[kv.group(1)!] = kv.group(2)!;
    }
    int? meters;
    final distance = fields['Distance'];
    if (distance != null) {
      final d = RegExp(r'^(\d+(?:\.\d+)?) km$').firstMatch(distance);
      if (d == null) throw CorosFormatException(tool, 'unreadable distance "$distance"');
      meters = (double.parse(d.group(1)!) * 1000).round();
    }
    final load = fields['Load'];
    int? tl;
    if (load != null) {
      final m = RegExp(r'^(\d+) TL$').firstMatch(load);
      if (m == null) throw CorosFormatException(tool, 'unreadable load "$load"');
      tl = int.parse(m.group(1)!);
    }
    final est = fields['Estimated Time'];
    result.putIfAbsent(lines.first, () => []).add(ScheduledWorkout(
          name: lines[1],
          distanceMeters: meters,
          estimatedSeconds: est == null ? null : parseClockSeconds(tool, est),
          trainingLoad: tl,
          planId: fields['Plan ID'],
        ));
  }
  return result;
}

// ---------------------------------------------------------------------------
// queryTrainingPlanDetails

class PlanCourse {
  PlanCourse({required this.name, required this.sport, required this.status, required this.courseJson});

  final String name;
  final WorkoutSport sport;

  /// As Coros writes it, for example "Not started".
  final String status;
  final String courseJson;
}

class PlanDetails {
  PlanDetails({required this.planId, required this.name, required this.days, this.startDate, this.endDate});

  final String planId;
  final String name;
  final Map<CorosDate, List<PlanCourse>> days;
  final CorosDate? startDate;
  final CorosDate? endDate;
}

PlanDetails parsePlanDetails(String text) {
  const tool = 'queryTrainingPlanDetails';
  _expectHeader(tool, text, 'Training Plan Detail');
  final lines = _lines(text);
  String? field(String key) => lines.map((l) => RegExp('^${RegExp.escape(key)}: (.+)\$').firstMatch(l.trim())).nonNulls.firstOrNull?.group(1);
  final planId = field('Plan ID') ?? (throw CorosFormatException(tool, 'no Plan ID'));
  final name = field('Name') ?? (throw CorosFormatException(tool, 'no plan Name'));

  final days = <CorosDate, List<PlanCourse>>{};
  CorosDate? date;
  String? status, courseName, courseJson, sportLabel;

  void flushCourse() {
    if (status == null) return;
    if (courseName == null || courseJson == null) throw CorosFormatException(tool, 'incomplete course on $date');
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(courseJson!) as Map<String, dynamic>;
    } on FormatException {
      throw CorosFormatException(tool, 'unreadable Course JSON on $date');
    }
    final code = json['sportType'];
    // Coros's own label wins when given ("sport type 4 (Strength)"); otherwise the documented codes.
    final sport = switch ((code, sportLabel)) {
      (_, 'Strength') => WorkoutSport.strength,
      (_, 'Rest') => WorkoutSport.rest,
      (1, _) => WorkoutSport.run,
      (2, _) => WorkoutSport.cycle,
      (5, _) => WorkoutSport.trailRun,
      _ => WorkoutSport.unknown,
    };
    days.putIfAbsent(date!, () => []).add(PlanCourse(name: courseName!, sport: sport, status: status!, courseJson: courseJson!));
    status = courseName = courseJson = sportLabel = null;
  }

  for (final raw in lines) {
    final line = raw.trim();
    final day = RegExp(r'^Day \d+ - (\d{4}-\d{2}-\d{2})$').firstMatch(line);
    if (day != null) {
      flushCourse();
      date = day.group(1);
      continue;
    }
    if (date == null) continue; // plan summary above the day rows
    final course = RegExp(r'^Course \d+ \[([^,\]]+)').firstMatch(line);
    if (course != null) {
      flushCourse();
      status = course.group(1)!.trim();
      continue;
    }
    if (line.startsWith('Course: ')) {
      courseName = line.substring('Course: '.length).trim();
    } else if (line.startsWith('Course JSON: ')) {
      courseJson = line.substring('Course JSON: '.length).trim();
    } else if (line.startsWith('Degradation: ')) {
      sportLabel = RegExp(r'sport type \d+ \(([^)]+)\)').firstMatch(line)?.group(1);
    }
    // Other lines are guidance for AI assistants (L6) and are ignored.
  }
  flushCourse();
  final dates = RegExp(r'^(\d{4}-\d{2}-\d{2}) to (\d{4}-\d{2}-\d{2})$').firstMatch(field('Dates') ?? '');
  return PlanDetails(planId: planId, name: name, days: days, startDate: dates?.group(1), endDate: dates?.group(2));
}

/// `yyyyMMdd` as used in Coros tool arguments.
String corosArgDate(DateTime d) =>
    '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

/// `yyyy-MM-dd` as used in Coros replies.
CorosDate corosDate(DateTime d) => _compactToIso(corosArgDate(d));

// ---------------------------------------------------------------------------
// queryUserInfo

class UserProfile {
  UserProfile({required this.nickname, this.heightCm, this.weightKg, this.age, this.gender});

  final String nickname;
  final double? heightCm;
  final double? weightKg;
  final int? age;
  final String? gender;
}

UserProfile parseUserInfo(String text) {
  const tool = 'queryUserInfo';
  _expectHeader(tool, text, 'User Profile Information');
  final fields = <String, String>{
    for (final m in RegExp(r'^([A-Za-z ]+): (.+)$', multiLine: true).allMatches(text)) m.group(1)!.trim(): m.group(2)!.trim(),
  };
  final nickname = fields['Nickname'];
  if (nickname == null) throw CorosFormatException(tool, 'no Nickname');
  double? number(String? v, String unit) => v == null ? null : double.tryParse(v.replaceAll(unit, '').trim());
  return UserProfile(
    nickname: nickname,
    heightCm: number(fields['Height'], 'cm'),
    weightKg: number(fields['Weight'], 'kg'),
    age: int.tryParse(RegExp(r'Age: (\d+)').firstMatch(fields['Birthday'] ?? '')?.group(1) ?? ''),
    gender: fields['Gender'],
  );
}

// ---------------------------------------------------------------------------
// queryActivityLapData. Unlike the other tools, this one returns JSON (L29).

class Split {
  Split({required this.distanceMeters, required this.seconds, this.avgHr});

  final double distanceMeters;
  final double seconds;
  final int? avgHr;

  double get paceSecondsPerKm => seconds / (distanceMeters / 1000);
}

Map<String, dynamic> _lapJson(String tool, String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw CorosFormatException(tool, 'lap data is not JSON');
  }
  if (decoded is! Map<String, dynamic> || decoded['lapGroups'] is! List) {
    throw CorosFormatException(tool, 'no lapGroups in lap data');
  }
  return decoded;
}

List<Map<String, dynamic>> _laps(Map<String, dynamic> group) => (group['laps'] as List? ?? []).cast<Map<String, dynamic>>();

/// The watch's automatic 1-km splits (lap group type 2). Distances arrive in centimetres.
/// A run without automatic splits (manual laps only) gives an empty list, not an error.
List<Split> parseRunSplits(String text) {
  const tool = 'queryActivityLapData';
  final json = _lapJson(tool, text);
  final group = (json['lapGroups'] as List).cast<Map<String, dynamic>>().where((g) => g['type'] == 2).firstOrNull;
  if (group == null) return [];
  return [
    for (final lap in _laps(group))
      if (lap['distance'] is num && lap['time'] is num)
        Split(
          distanceMeters: (lap['distance'] as num) / 100,
          seconds: (lap['time'] as num).toDouble(),
          avgHr: (lap['avgHr'] as num?)?.toInt(),
        )
      else
        throw CorosFormatException(tool, 'split without distance or time'),
  ];
}

class StrengthSummary {
  StrengthSummary({required this.bodyParts, required this.workSets, required this.reps});

  /// As Coros names them, for example "Legs/Hips".
  final Set<String> bodyParts;
  final int workSets;
  final int reps;
}

/// Work sets are laps with reps and no "sets" total; rest intervals have no reps, and the
/// closing summary laps carry the session totals in "sets".
StrengthSummary parseStrengthLaps(String text) {
  const tool = 'queryActivityLapData';
  final json = _lapJson(tool, text);
  final laps = (json['lapGroups'] as List).cast<Map<String, dynamic>>().expand(_laps).toList();
  final work = [
    for (final lap in laps)
      if ((lap['reps'] as num? ?? 0) > 0 && (lap['sets'] as num? ?? 0) == 0 && lap['exerciseNameKey'] != 'Rest') lap,
  ];
  for (final lap in work) {
    if (lap['exerciseNameKey'] is! String) throw CorosFormatException(tool, 'strength set without exerciseNameKey');
  }
  return StrengthSummary(
    bodyParts: {for (final lap in work) lap['exerciseNameKey'] as String},
    workSets: work.length,
    reps: work.fold(0, (sum, lap) => sum + (lap['reps'] as num).toInt()),
  );
}

// ---------------------------------------------------------------------------
// queryDailyHealthData: only the active calories are used (food targets, M4). Its other
// values disagree with the dedicated tools (L8, L15, L18), so they are ignored.

/// Active calories per day. "Calories" is active energy, not total (checked 5 Oct 2026:
/// 540 kcal by evening on a 35-minute day). A day without a Calories field maps to null.
Map<CorosDate, int?> parseDailyHealth(String text) {
  const tool = 'queryDailyHealthData';
  _expectHeader(tool, text, 'Daily Health Data');
  final result = <CorosDate, int?>{};
  CorosDate? day;
  for (final line in _lines(text)) {
    final header = RegExp(r'^--- (\d{8}) ---$').firstMatch(line.trim());
    if (header != null) {
      day = _compactToIso(header.group(1)!);
      result[day] = null;
      continue;
    }
    if (day == null || !line.startsWith('Steps:') && !line.startsWith('Calories:')) continue;
    final kcal = RegExp(r'(?:^|\| )Calories: ([\d,]+) kcal').firstMatch(line);
    if (kcal != null) result[day] = int.parse(kcal.group(1)!.replaceAll(',', ''));
  }
  if (result.isEmpty) throw CorosFormatException(tool, 'no days in reply');
  return result;
}

// ---------------------------------------------------------------------------
// queryActivityFitFileDownloadUrls (M5). Checked 7 Oct 2026: a plain S3 address, no
// login needed, so the app fetches it straight to the phone and never shares it.

Uri parseFitUrl(String text) {
  const tool = 'queryActivityFitFileDownloadUrls';
  _expectHeader(tool, text, 'Activity FIT file download URL');
  final m = RegExp(r'^\s*(https://\S+\.fit)\s*$', multiLine: true).firstMatch(text);
  if (m == null) throw CorosFormatException(tool, 'no .fit URL in reply');
  final url = Uri.parse(m.group(1)!);
  if (url.host != 's3.coros.com') throw CorosFormatException(tool, 'unexpected host ${url.host}');
  return url;
}
