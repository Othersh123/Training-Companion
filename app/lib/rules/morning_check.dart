/// The morning verdict, from fixed rules the user can read (PRD: Core logic, Morning verdict).
/// Pure Dart: reads parsed Coros data only, so it runs offline and is unit-tested on real history.
library;

import '../coros/parsers.dart';
import 'planned_workout.dart';

/// Every threshold is editable in Settings. Defaults confirmed by the owner on 2 Oct 2026.
class Thresholds {
  const Thresholds({
    this.restingHrRiseBpm = 5,
    this.restingHrHistoryDays = 30,
    this.restingHrMinHistory = 7,
    this.sleepMinMinutes = 6 * 60,
    this.excessiveLoadLabel = 'Excessive',
    this.easyRunMaxMinutes = 60,
  });

  final int restingHrRiseBpm;
  final int restingHrHistoryDays;

  /// Fewer days than this with a resting HR in the window means no baseline yet.
  final int restingHrMinHistory;
  final int sleepMinMinutes;
  final String excessiveLoadLabel;

  /// Until M3 adds plan labels, runs shorter than this count as easy.
  final int easyRunMaxMinutes;
}

/// Data from one Coros tool: either parsed, or the reason it couldn't be read.
class Source<T> {
  const Source.ok(T this.data) : error = null;
  const Source.failed(String this.error) : data = null;

  final T? data;
  final String? error;
}

enum Signal { hrv, restingHr, sleep, load }

enum SignalState { clear, flagged, noData, error }

class SignalResult {
  const SignalResult(this.signal, this.state, {this.value, this.normal, this.note});

  final Signal signal;
  final SignalState state;

  /// Today's value as shown, for example "91 ms".
  final String? value;

  /// The user's normal, for example "93 to 111 ms".
  final String? normal;

  /// Why it's flagged, missing or in error.
  final String? note;

  bool get hasData => state == SignalState.clear || state == SignalState.flagged;
}

enum Verdict { goAsPlanned, goEasy, rest, notEnoughData }

enum EasyRunState { noEasyRun, underCap, overCap, capNotSet }

class EasyRunCheck {
  const EasyRunCheck(this.state, {this.avgHr, this.cap, this.runName});

  final EasyRunState state;
  final int? avgHr;
  final int? cap;
  final String? runName;
}

class MorningCheck {
  MorningCheck({required this.date, required this.verdict, required this.signals, required this.reason, required this.easyRun});

  final CorosDate date;
  final Verdict verdict;
  final List<SignalResult> signals;

  /// One line naming what drove the verdict, for the widget and notification.
  final String reason;
  final EasyRunCheck easyRun;

  bool get hasErrors => signals.any((s) => s.state == SignalState.error);
}

MorningCheck computeMorningCheck({
  required DateTime today,
  required Source<Map<CorosDate, HrvNight?>> hrv,
  required Source<Map<CorosDate, int?>> restingHr,
  required Source<Map<CorosDate, SleepDay>> sleep,
  required Source<Map<CorosDate, LoadDay>> load,
  required Source<List<Activity>> activities,
  int? easyRunHrCap,

  /// Yesterday's plan, if any: its structure says whether the run was meant to be easy (M3).
  List<ScheduledWorkout>? plannedYesterday,
  Thresholds t = const Thresholds(),
}) {
  final date = corosDate(today);
  final signals = [
    _hrvSignal(hrv, date),
    _restingHrSignal(restingHr, today, t),
    _sleepSignal(sleep, date, t),
    _loadSignal(load, date, t),
  ];

  final withData = signals.where((s) => s.hasData).length;
  final flagged = signals.where((s) => s.state == SignalState.flagged).toList();
  final verdict = withData < 2
      ? Verdict.notEnoughData
      : switch (flagged.length) {
          0 => Verdict.goAsPlanned,
          1 => Verdict.goEasy,
          _ => Verdict.rest,
        };

  return MorningCheck(
    date: date,
    verdict: verdict,
    signals: signals,
    reason: _reason(verdict, signals, flagged),
    easyRun: _easyRunCheck(activities, today, easyRunHrCap, t, plannedYesterday),
  );
}

SignalResult _hrvSignal(Source<Map<CorosDate, HrvNight?>> src, CorosDate date) {
  if (src.error != null) return SignalResult(Signal.hrv, SignalState.error, note: src.error);
  final night = src.data![date];
  if (night == null) return const SignalResult(Signal.hrv, SignalState.noData, note: 'No HRV for last night');
  final below = night.rating == HrvRating.belowNormal || night.rating == HrvRating.low;
  return SignalResult(
    Signal.hrv,
    below ? SignalState.flagged : SignalState.clear,
    value: '${night.avgMs} ms',
    normal: '${night.rangeLowMs} to ${night.rangeHighMs} ms',
    // Notes name their signal: they become the reason line in the notification and widget.
    note: below ? 'HRV ${night.avgMs} ms, below your ${night.rangeLowMs} to ${night.rangeHighMs} ms range' : null,
  );
}

SignalResult _restingHrSignal(Source<Map<CorosDate, int?>> src, DateTime today, Thresholds t) {
  if (src.error != null) return SignalResult(Signal.restingHr, SignalState.error, note: src.error);
  final byDate = src.data!;
  final value = byDate[corosDate(today)];
  if (value == null) return const SignalResult(Signal.restingHr, SignalState.noData, note: 'No resting HR for today');

  final history = [
    for (var d = 1; d <= t.restingHrHistoryDays; d++) byDate[corosDate(today.subtract(Duration(days: d)))],
  ].whereType<int>().toList();
  if (history.length < t.restingHrMinHistory) {
    return SignalResult(Signal.restingHr, SignalState.noData,
        value: '$value bpm', note: 'Needs ${t.restingHrMinHistory}+ days of history, has ${history.length}');
  }
  final avg = history.reduce((a, b) => a + b) / history.length;
  final rise = value - avg;
  final high = rise >= t.restingHrRiseBpm;
  return SignalResult(
    Signal.restingHr,
    high ? SignalState.flagged : SignalState.clear,
    value: '$value bpm',
    normal: '${t.restingHrHistoryDays}-day average ${avg.toStringAsFixed(0)} bpm',
    note: high ? 'Resting HR $value bpm, ${rise.toStringAsFixed(0)} above your average' : null,
  );
}

SignalResult _sleepSignal(Source<Map<CorosDate, SleepDay>> src, CorosDate date, Thresholds t) {
  if (src.error != null) return SignalResult(Signal.sleep, SignalState.error, note: src.error);
  final minutes = src.data![date]?.mainAsleepMinutes;
  if (minutes == null) return const SignalResult(Signal.sleep, SignalState.noData, note: 'No night sleep recorded');
  final short = minutes < t.sleepMinMinutes;
  return SignalResult(
    Signal.sleep,
    short ? SignalState.flagged : SignalState.clear,
    value: formatMinutes(minutes),
    normal: '${formatMinutes(t.sleepMinMinutes)} or more',
    note: short ? 'Short night: ${formatMinutes(minutes)} asleep' : null,
  );
}

SignalResult _loadSignal(Source<Map<CorosDate, LoadDay>> src, CorosDate date, Thresholds t) {
  if (src.error != null) return SignalResult(Signal.load, SignalState.error, note: src.error);
  final day = src.data![date];
  if (day == null) return const SignalResult(Signal.load, SignalState.noData, note: 'No load assessment for today');
  final excessive = day.label == t.excessiveLoadLabel;
  return SignalResult(
    Signal.load,
    excessive ? SignalState.flagged : SignalState.clear,
    value: '${day.ratio.toStringAsFixed(2)} ${day.label}',
    normal: 'Not ${t.excessiveLoadLabel}',
    note: excessive ? 'Load ${day.ratio.toStringAsFixed(2)}, rated ${day.label} by Coros' : null,
  );
}

EasyRunCheck _easyRunCheck(Source<List<Activity>> src, DateTime today, int? cap, Thresholds t, List<ScheduledWorkout>? planned) {
  if (src.data == null) return const EasyRunCheck(EasyRunState.noEasyRun);
  final yesterday = corosDate(today.subtract(const Duration(days: 1)));
  final ran = src.data!.where((a) => a.date == yesterday && a.isRun && a.avgHr != null).toList();
  final easyRuns = switch (isPlannedEasyDay(yesterday, planned)) {
    true => ran, // the plan said easy
    false => <Activity>[], // the plan said long or hard
    null => ran.where((a) => a.durationSeconds < t.easyRunMaxMinutes * 60).toList(), // no plan: duration rule
  };
  if (easyRuns.isEmpty) return const EasyRunCheck(EasyRunState.noEasyRun);
  if (cap == null) return EasyRunCheck(EasyRunState.capNotSet, avgHr: easyRuns.first.avgHr, runName: easyRuns.first.name);
  // With several easy runs, report the hardest one.
  easyRuns.sort((a, b) => b.avgHr!.compareTo(a.avgHr!));
  final run = easyRuns.first;
  return EasyRunCheck(run.avgHr! <= cap ? EasyRunState.underCap : EasyRunState.overCap,
      avgHr: run.avgHr, cap: cap, runName: run.name);
}

String _reason(Verdict verdict, List<SignalResult> signals, List<SignalResult> flagged) {
  if (verdict == Verdict.notEnoughData) {
    final missing = signals.where((s) => !s.hasData).map((s) => signalLabel(s.signal)).join(', ');
    return 'Not enough data: missing $missing';
  }
  if (flagged.isEmpty) return 'All signals in your normal range';
  return flagged.map((s) => s.note ?? signalLabel(s.signal)).join(' · ');
}

String signalLabel(Signal s) => switch (s) {
      Signal.hrv => 'HRV',
      Signal.restingHr => 'Resting HR',
      Signal.sleep => 'Sleep',
      Signal.load => 'Load',
    };

String verdictLabel(Verdict v) => switch (v) {
      Verdict.goAsPlanned => 'Go as planned',
      Verdict.goEasy => 'Go easy',
      Verdict.rest => 'Rest',
      Verdict.notEnoughData => 'Not enough data',
    };

String formatMinutes(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '${m}m';
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

