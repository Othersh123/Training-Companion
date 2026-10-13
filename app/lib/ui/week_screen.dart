import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../food/week_food.dart';
import '../sync/food_day.dart';
import '../coros/parsers.dart' show corosDate;
import '../data/goal.dart';
import '../rules/morning_check.dart' show formatMinutes;
import '../rules/weekly_review.dart';
import 'charts.dart';
import 'places_screen.dart';
import 'theme.dart';

const _days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String weekLabel(DateTime monday) {
  final sunday = monday.add(const Duration(days: 6));
  return monday.month == sunday.month
      ? '${monday.day} to ${sunday.day} ${_months[sunday.month - 1]}'
      : '${monday.day} ${_months[monday.month - 1]} to ${sunday.day} ${_months[sunday.month - 1]}';
}

/// PRD F3: the weekly review, with history back to the 12-week baseline.
class WeekScreen extends StatefulWidget {
  const WeekScreen({super.key});

  @override
  State<WeekScreen> createState() => _WeekScreenState();
}

class _WeekScreenState extends State<WeekScreen> {
  static const historyWeeks = 12;
  late DateTime _monday = mondayOf(DateTime.now());
  WeekReview? _review;
  WeekFood? _food;
  String? _error;

  DateTime get _thisMonday => mondayOf(DateTime.now());

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  String? _loadError;

  Future<void> _load() async {
    final app = AppScope.of(context);
    try {
      await app.screenLoad('Week', () => _loadData(app));
      _loadError = null;
    } catch (e) {
      if (mounted) setState(() => _loadError = 'Couldn\'t load this week ($e). Pull down to try again.');
    }
  }

  Future<void> _loadData(AppController app) async {
    final review = await app.sync.weekReviewFromDatabase(_monday);
    final food = await app.sync.weekFoodFromDatabase(_monday, review);
    // Longest run in the 4 weeks to the end of this week, for race goal progress.
    final end = _monday.add(const Duration(days: 6));
    final recent = await app.db.activitiesBetween(corosDate(end.subtract(const Duration(days: 27))), corosDate(end));
    final longest = recent.where((a) => a.isRun).fold(0.0, (m, a) => (a.distanceMeters ?? 0) / 1000 > m ? (a.distanceMeters ?? 0) / 1000 : m);
    if (mounted) {
      setState(() {
        _review = review;
        _food = food;
        _longest4w = longest;
      });
    }
  }

  double _longest4w = 0;

  Future<void> _refresh() async {
    final app = AppScope.of(context);
    try {
      await app.sync.syncWeek(_monday, DateTime.now());
      _error = null;
    } catch (e) {
      _error = 'Couldn\'t reach Coros; showing what\'s stored.';
    }
    await _load();
  }

  void _shift(int weeks) {
    final next = _monday.add(Duration(days: 7 * weeks));
    if (next.isAfter(_thisMonday) || next.isBefore(_thisMonday.subtract(const Duration(days: 7 * historyWeeks)))) return;
    setState(() {
      _monday = next;
      _review = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final r = _review;
    return RefreshIndicator(
      color: Tc.go,
      backgroundColor: Tc.surface,
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
        children: [
          Text('Week', style: Tc.title(34)),
          const SizedBox(height: 16),
          _WeekPicker(
            label: _monday == _thisMonday ? 'This week · ${weekLabel(_monday)}' : weekLabel(_monday),
            canBack: _monday.isAfter(_thisMonday.subtract(const Duration(days: 7 * historyWeeks))),
            canForward: _monday.isBefore(_thisMonday),
            onBack: () => _shift(-1),
            onForward: () => _shift(1),
          ),
          if (_error != null) ...[const SizedBox(height: 10), Text(_error!, style: Tc.label.copyWith(color: Tc.coral, fontSize: 13))],
          const SizedBox(height: 16),
          if (r == null && _loadError != null)
            EmptyCard(icon: Icons.error_outline, title: 'Week didn\'t load', subtitle: _loadError!)
          else if (r == null)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: Tc.go)))
          else ...[
            _OneThingCard(r: r),
            const SizedBox(height: 12),
            _VolumeCard(r: r),
            const SizedBox(height: 12),
            _StatRow(r: r),
            const SizedBox(height: 12),
            _PlanCard(r: r),
            const SizedBox(height: 12),
            _FitnessCard(r: r, onOpen: () => _openTrend(TrendMetric.fitness)),
            const SizedBox(height: 12),
            _RecoveryCard(r: r),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in TrendMetric.values)
                ActionChip(
                  label: Text('${m.label} trend', style: Tc.body.copyWith(fontSize: 13)),
                  backgroundColor: Tc.surfaceRaised,
                  side: const BorderSide(color: Tc.hairline),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                  onPressed: () => _openTrend(m),
                ),
            ]),
            const SizedBox(height: 24),
            _GoalProgress(review: r, longest4w: _longest4w, food: _food),
            const SizedBox(height: 12),
            if (_food != null) _BodyFoodCard(f: _food!),
            const SizedBox(height: 12),
            const PlacesCard(),
          ],
        ],
      ),
    );
  }

  void _openTrend(TrendMetric metric) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => TrendScreen(initial: metric, endMonday: _thisMonday)));
}

class _WeekPicker extends StatelessWidget {
  const _WeekPicker({required this.label, required this.canBack, required this.canForward, required this.onBack, required this.onForward});
  final String label;
  final bool canBack, canForward;
  final VoidCallback onBack, onForward;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: Tc.surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: Tc.hairline)),
        child: Row(children: [
          IconButton(onPressed: canBack ? onBack : null, icon: const Icon(Icons.chevron_left_rounded), color: Tc.text, disabledColor: Tc.muted),
          Expanded(child: Text(label, textAlign: TextAlign.center, style: Tc.body.copyWith(fontWeight: FontWeight.w500))),
          IconButton(onPressed: canForward ? onForward : null, icon: const Icon(Icons.chevron_right_rounded), color: Tc.text, disabledColor: Tc.muted),
        ]),
      );
}

class _OneThingCard extends StatelessWidget {
  const _OneThingCard({required this.r});
  final WeekReview r;

  @override
  Widget build(BuildContext context) {
    final onTrack = r.oneThing.kind == ChangeKind.onTrack;
    final color = onTrack ? Tc.go : Tc.amber;
    return TcCard(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [color.withValues(alpha: 0.2), Tc.surface],
        stops: const [0, 0.6],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(r.complete ? 'FOR NEXT WEEK' : 'THIS WEEK, SO FAR', style: Tc.caps),
        const SizedBox(height: 10),
        Text(r.oneThing.text, style: Tc.title(20).copyWith(height: 1.3)),
      ]),
    );
  }
}

class _VolumeCard extends StatelessWidget {
  const _VolumeCard({required this.r});
  final WeekReview r;

  @override
  Widget build(BuildContext context) {
    final change = r.volumeChangePercent;
    final anyExcessive = r.dailyLoad.any((l) => l?.label == 'Excessive');
    return TcCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('Running', style: Tc.label),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              !r.complete
                  ? (r.previousAvgKm == null ? 'So far' : 'So far · weekly avg ${r.previousAvgKm!.toStringAsFixed(0)} km')
                  : (change == null ? '' : '${change >= 0 ? '+' : ''}${change.toStringAsFixed(0)}% vs 3-week avg'),
              textAlign: TextAlign.end,
              style: Tc.label.copyWith(fontSize: 13, color: r.complete && (change ?? 0) > 10 ? Tc.amber : Tc.textSecondary),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text(r.kmRun.toStringAsFixed(1), style: Tc.title(40)),
          const SizedBox(width: 6),
          Text('km', style: Tc.label),
        ]),
        const SizedBox(height: 8),
        BarChart(data: [
          for (var i = 0; i < 7; i++)
            BarDatum(
              label: _days[i],
              value: r.dailyKm[i],
              valueLabel: r.dailyKm[i] > 0 ? r.dailyKm[i].toStringAsFixed(1) : null,
              flagged: r.dailyLoad[i]?.label == 'Excessive',
              tooltip: '${_dayNames[i]} · ${r.dailyKm[i].toStringAsFixed(1)} km'
                  '${r.dailyLoad[i] == null ? '' : ' · load ${r.dailyLoad[i]!.ratio.toStringAsFixed(2)} ${r.dailyLoad[i]!.label}'}',
            ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: Tc.amber, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                anyExcessive
                    ? 'Excessive load: ${r.excessiveDays} day${r.excessiveDays == 1 ? '' : 's'}'
                    : (r.dailyLoad.every((l) => l == null) ? 'No load data for this week' : 'No days in Excessive load'),
                style: Tc.label.copyWith(fontSize: 13)),
          ),
        ]),
      ]),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.r});
  final WeekReview r;

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, String value, {Color color = Tc.text}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: Tc.label.copyWith(fontSize: 13)),
            const SizedBox(height: 4),
            Text(value, style: Tc.title(20).copyWith(color: color)),
          ]),
        );
    final compliance = r.compliance;
    return TcCard(
      child: Row(children: [
        stat('Easy runs', r.easyRuns == 0 ? 'None' : '${r.easyUnderCap} of ${r.easyRuns}',
            color: compliance == null ? Tc.text : (compliance >= 0.8 ? Tc.go : Tc.amber)),
        stat('Strength', '${r.strengthDone} of ${r.strengthPlanned}', color: r.strengthDone >= r.strengthPlanned ? Tc.go : Tc.amber),
        stat('Longest run', r.longestRunKm == 0 ? 'None' : '${r.longestRunKm.toStringAsFixed(1)} km'),
      ]),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.r});
  final WeekReview r;

  @override
  Widget build(BuildContext context) {
    Widget row(String label, String value, String? note) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: Tc.label),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(value, textAlign: TextAlign.end, style: Tc.body.copyWith(fontWeight: FontWeight.w500)),
                if (note != null) Text(note, textAlign: TextAlign.end, style: Tc.label.copyWith(fontSize: 12)),
              ]),
            ),
          ]),
        );
    return TcCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('PLAN AGAINST DONE', style: Tc.caps),
        const SizedBox(height: 6),
        row('Runs', r.runsPlanned == null ? '${r.runsDone} done' : '${r.runsDone} of ${r.runsPlanned} planned',
            r.runsPlanned == null ? 'No Coros plan this week' : null),
        const Divider(height: 1, color: Tc.hairline),
        row('Strength', '${r.strengthDone} of ${r.strengthPlanned}', r.strengthFromPlan ? 'From your Coros plan' : 'Default target: 2 a week'),
        if (r.bodyParts.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final part in r.bodyParts)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Tc.surfaceRaised, borderRadius: BorderRadius.circular(999)),
                child: Text(part, style: Tc.body.copyWith(fontSize: 13)),
              ),
          ]),
        ],
      ]),
    );
  }
}

class _FitnessCard extends StatelessWidget {
  const _FitnessCard({required this.r, required this.onOpen});
  final WeekReview r;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final f = r.fitness;
    return GestureDetector(
      onTap: onOpen,
      child: TcCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Aerobic fitness', style: Tc.label)),
            const Icon(Icons.chevron_right_rounded, color: Tc.textSecondary),
          ]),
          const SizedBox(height: 6),
          if (f == null)
            Text(
              r.settings.easyRunHrCap == null
                  ? 'Set your easy-run HR cap in Settings to track this.'
                  : 'Not enough easy runs near home with splits this week.',
              style: Tc.body.copyWith(fontSize: 14, color: Tc.textSecondary),
            )
          else ...[
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Text(formatPace(f.paceSecondsPerKm), style: Tc.title(36)),
              const SizedBox(width: 6),
              Text('/km', style: Tc.label),
              if (f.estimated) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Tc.surfaceRaised, borderRadius: BorderRadius.circular(999)),
                  child: Text('estimated', style: Tc.label.copyWith(fontSize: 12)),
                ),
              ],
            ]),
            const SizedBox(height: 4),
            Text(
              f.estimated
                  ? 'Your pace at ${f.bandHigh} bpm, estimated from ${f.splits} splits. Too few km were run at ${f.bandLow} to ${f.bandHigh} bpm to measure it directly.'
                  : 'Median pace of ${f.splits} km splits at ${f.bandLow} to ${f.bandHigh} bpm, on easy runs near home. Faster over time means fitter.',
              style: Tc.label.copyWith(fontSize: 13),
            ),
          ],
        ]),
      ),
    );
  }
}

class _RecoveryCard extends StatelessWidget {
  const _RecoveryCard({required this.r});
  final WeekReview r;

  @override
  Widget build(BuildContext context) {
    final rhr = r.restingHrAvg, prev = r.previousRestingHrAvg;
    final rhrChange = rhr == null || prev == null ? null : rhr - prev;
    return TcCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('RECOVERY', style: Tc.caps),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Average sleep', style: Tc.label.copyWith(fontSize: 13)),
              const SizedBox(height: 4),
              Text(r.sleepAvgMinutes == null ? 'No data' : formatMinutes(r.sleepAvgMinutes!), style: Tc.title(20)),
              Text('${r.shortNights} of ${r.sleepNights} nights under ${r.settings.sleepMinMinutes ~/ 60}h',
                  style: Tc.label.copyWith(fontSize: 12, color: r.shortNights >= 2 ? Tc.amber : Tc.textSecondary)),
            ]),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Resting HR', style: Tc.label.copyWith(fontSize: 13)),
              const SizedBox(height: 4),
              Text(rhr == null ? 'No data' : '${rhr.toStringAsFixed(0)} bpm', style: Tc.title(20)),
              if (rhrChange != null)
                Text('${rhrChange >= 0 ? 'Up' : 'Down'} ${rhrChange.abs().toStringAsFixed(1)} on last week',
                    style: Tc.label.copyWith(fontSize: 12, color: rhrChange >= 3 ? Tc.amber : Tc.textSecondary)),
            ]),
          ),
        ]),
      ]),
    );
  }
}

enum TrendMetric {
  km('Km'),
  easyRuns('Easy runs'),
  strength('Strength'),
  fitness('Fitness'),
  sleep('Sleep'),
  restingHr('Resting HR');

  const TrendMetric(this.label);
  final String label;
}

/// "Open a metric's trend" (PRD screens table): 12 weeks back to the baseline, with a table view.
class TrendScreen extends StatefulWidget {
  const TrendScreen({super.key, required this.initial, required this.endMonday});
  final TrendMetric initial;
  final DateTime endMonday;

  @override
  State<TrendScreen> createState() => _TrendScreenState();
}

class _TrendScreenState extends State<TrendScreen> {
  late TrendMetric _metric = widget.initial;
  List<WeekReview>? _weeks;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_weeks == null) _load();
  }

  Future<void> _load() async {
    final sync = AppScope.of(context).sync;
    final weeks = <WeekReview>[];
    for (var i = 11; i >= 0; i--) {
      weeks.add(await sync.weekReviewFromDatabase(widget.endMonday.subtract(Duration(days: 7 * i))));
    }
    if (mounted) setState(() => _weeks = weeks);
  }

  double? _value(WeekReview r) => switch (_metric) {
        TrendMetric.km => r.kmRun,
        TrendMetric.easyRuns => r.compliance == null ? null : r.compliance! * 100,
        TrendMetric.strength => r.strengthDone.toDouble(),
        TrendMetric.fitness => r.fitness?.paceSecondsPerKm,
        TrendMetric.sleep => r.sleepAvgMinutes?.toDouble(),
        TrendMetric.restingHr => r.restingHrAvg,
      };

  String _format(double v) => switch (_metric) {
        TrendMetric.km => '${v.toStringAsFixed(1)} km',
        TrendMetric.easyRuns => '${v.toStringAsFixed(0)}% under cap',
        TrendMetric.strength => '${v.toStringAsFixed(0)} sessions',
        TrendMetric.fitness => '${formatPace(v)} /km',
        TrendMetric.sleep => formatMinutes(v.round()),
        TrendMetric.restingHr => '${v.toStringAsFixed(0)} bpm',
      };

  String get _note => switch (_metric) {
        TrendMetric.fitness => 'Lower is better: faster at the same easy heart rate. Hollow points are estimates.',
        TrendMetric.easyRuns => 'Target: 80% of easy runs at or under your cap.',
        TrendMetric.strength => 'Target: 2 a week, in 3 of every 4 weeks.',
        TrendMetric.sleep => 'Average of nights with data; naps excluded.',
        TrendMetric.restingHr => 'Weekly average. A rising trend can mean fatigue or illness.',
        TrendMetric.km => 'Weekly volume should rise no more than 10% on the previous 3 weeks.',
      };

  @override
  Widget build(BuildContext context) {
    final weeks = _weeks;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: Tc.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: Tc.hairline)),
                  child: const Icon(Icons.arrow_back_rounded, color: Tc.text, size: 20),
                ),
              ),
              const SizedBox(width: 14),
              Text('12-week trend', style: Tc.title(26)),
            ]),
            const SizedBox(height: 18),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final m in TrendMetric.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(m.label),
                      selected: m == _metric,
                      onSelected: (_) => setState(() => _metric = m),
                      selectedColor: Tc.goButton,
                      backgroundColor: Tc.surfaceRaised,
                      labelStyle: TextStyle(fontFamily: Tc.font, color: m == _metric ? Colors.black : Tc.text),
                      showCheckmark: false,
                      side: const BorderSide(color: Tc.hairline),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 16),
            if (weeks == null)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: Tc.go)))
            else ...[
              TcCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_metric.label, style: Tc.label),
                  const SizedBox(height: 8),
                  TrendLine(
                    values: weeks.map(_value).toList(),
                    labels: weeks.map((w) => weekLabel(w.monday)).toList(),
                    format: _format,
                    markEstimated: _metric == TrendMetric.fitness ? weeks.map((w) => w.fitness?.estimated ?? false).toList() : null,
                  ),
                  const SizedBox(height: 10),
                  Text(_note, style: Tc.label.copyWith(fontSize: 13)),
                ]),
              ),
              const SizedBox(height: 16),
              Text('BY WEEK', style: Tc.caps),
              const SizedBox(height: 8),
              TcCard(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                child: Column(children: [
                  for (final (i, w) in weeks.reversed.indexed) ...[
                    if (i > 0) const Divider(height: 1, color: Tc.hairline),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(children: [
                        Expanded(child: Text(weekLabel(w.monday), style: Tc.label.copyWith(fontSize: 14))),
                        Text(
                          _value(w) == null ? 'No data' : _format(_value(w)!) + (_metric == TrendMetric.fitness && w.fitness!.estimated ? ' (est.)' : ''),
                          style: Tc.body.copyWith(fontSize: 14),
                        ),
                      ]),
                    ),
                  ],
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Goal progress (PRD F3): where you stand on each active goal this week.
class _GoalProgress extends StatelessWidget {
  const _GoalProgress({required this.review, required this.longest4w, required this.food});
  final WeekReview review;
  final double longest4w;
  final WeekFood? food;

  @override
  Widget build(BuildContext context) {
    final goals = AppScope.of(context).goals;
    if (goals.isEmpty) {
      return const EmptyCard(icon: Icons.flag_outlined, title: 'Goal progress', subtitle: 'Set a goal on the Plan tab to track it here.');
    }
    String line(Goal g) {
      final r = review;
      switch (g.type) {
        case GoalType.race:
          final days = g.daysTo(DateTime.now());
          final when = days == null ? '' : (days >= 0 ? '$days days to go. ' : 'Race day has passed. ');
          final dist = g.distanceMeters == null ? '' : ' (race: ${(g.distanceMeters! / 1000).toStringAsFixed(0)} km)';
          return '${when}Longest run in the last 4 weeks: ${longest4w.toStringAsFixed(1)} km$dist.';
        case GoalType.weight:
          final avg = food?.weightAvg;
          if (avg == null) return 'No weight logged in the last 7 days. Log it from the + button.';
          final toGo = avg - (g.targetWeightKg ?? avg);
          return '7-day average ${avg.toStringAsFixed(1)} kg, ${toGo > 0 ? '${toGo.toStringAsFixed(1)} kg to go' : 'at or under target'}'
              '${g.date == null ? '' : ' by ${g.date!.day} ${_months[g.date!.month - 1]}'}.';
        case GoalType.consistency:
          return '${r.runsDone} of ${g.runsPerWeek} runs and ${r.strengthDone} of ${g.strengthPerWeek} strength sessions this week.';
        case GoalType.aerobic:
          final f = r.fitness;
          return f == null
              ? 'No fitness reading this week. See the Fitness trend.'
              : 'This week: ${formatPace(f.paceSecondsPerKm)} /km at ${f.bandLow} to ${f.bandHigh} bpm${f.estimated ? ' (estimated)' : ''}. See the Fitness trend.';
      }
    }

    return TcCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('GOAL PROGRESS', style: Tc.caps),
        for (final g in goals) ...[
          const SizedBox(height: 12),
          Text(g.name, style: Tc.body.copyWith(fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(line(g), style: Tc.label.copyWith(fontSize: 13)),
        ],
      ]),
    );
  }
}

/// Body and food for the week (PRD F3): weight trend, days logged, protein and calories
/// against target, and the under-fuelling flag.
class _BodyFoodCard extends StatelessWidget {
  const _BodyFoodCard({required this.f});
  final WeekFood f;

  @override
  Widget build(BuildContext context) {
    final avg = f.weightAvg, prev = f.previousWeightAvg;
    final change = avg != null && prev != null ? avg - prev : null;
    Widget stat(String label, String value) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: Tc.label.copyWith(fontSize: 12)),
            const SizedBox(height: 4),
            Text(value, style: Tc.title(18)),
          ]),
        );
    return TcCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('BODY AND FOOD', style: Tc.caps),
        const SizedBox(height: 12),
        Row(children: [
          stat('Weight, 7-day avg', avg == null ? '–' : '${avg.toStringAsFixed(1)} kg'),
          stat('Change on last week', change == null ? '–' : '${change >= 0 ? '+' : '−'}${change.abs().toStringAsFixed(1)} kg'),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          stat('Days logged', '${f.daysLogged} of ${f.daysCounted}'),
          stat('Protein on target', '${f.proteinDays} of ${f.daysLogged}'),
          stat('Calories on target', '${f.kcalDays} of ${f.daysLogged}'),
        ]),
        const SizedBox(height: 10),
        Text('On target: protein at 90% or more, calories within 10%. Targets are estimates.', style: Tc.label.copyWith(fontSize: 12)),
        if (f.underFuelling != null) ...[
          const SizedBox(height: 12),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.warning_amber_rounded, color: Tc.amber, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('Under-fuelling: ${f.underFuelling}', style: Tc.body.copyWith(fontSize: 14, height: 1.35))),
          ]),
        ],
      ]),
    );
  }
}
