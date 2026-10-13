import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../rules/goal_status.dart';
import '../rules/insights.dart';
import '../rules/morning_check.dart';
import '../rules/weekly_review.dart' show formatPace;
import '../sync/home_data.dart';
import 'theme.dart';

Color trackColor(Track t) => switch (t) {
      Track.onTrack => Tc.go,
      Track.watch => Tc.amber,
      Track.offTrack => Tc.coral,
      Track.unknown => Tc.textSecondary,
    };

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _d(DateTime d) => '${d.day} ${_months[d.month - 1]}';

/// On track, Watch, Off track: always a label next to the colour.
class StatusPill extends StatelessWidget {
  const StatusPill(this.track, {super.key});
  final Track track;

  @override
  Widget build(BuildContext context) {
    final color = trackColor(track);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999), border: Border.all(color: color.withValues(alpha: 0.5))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(track.label, style: Tc.body.copyWith(fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// A goal on Home, drawn rather than described (owner, 7 Oct 2026). Tapping opens Plan,
/// where [GoalCard] gives the full reasons.
class GoalTile extends StatelessWidget {
  const GoalTile({super.key, required this.status, required this.primary, required this.onOpen});
  final GoalStatus status;
  final bool primary;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final color = trackColor(status.track);
    final body = switch (status.visual) {
      RaceVisual v => _RaceBody(status: status, v: v),
      WeightVisual v => _WeightBody(status: status, v: v),
      ConsistencyVisual v => _ConsistencyBody(status: status, v: v),
      AerobicVisual v => _AerobicBody(status: status, v: v),
      _ => _Header(status: status, big: status.headline, unit: ''),
    };
    return GestureDetector(
      onTap: onOpen,
      child: TcCard(
        gradient: primary
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color.withValues(alpha: 0.16), Tc.surface, Tc.surface],
                stops: const [0, 0.55, 1],
              )
            : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          body,
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Text(status.short, style: Tc.body.copyWith(fontSize: 14), maxLines: 2, overflow: TextOverflow.ellipsis)),
            const Icon(Icons.chevron_right_rounded, color: Tc.textSecondary, size: 20),
          ]),
        ]),
      ),
    );
  }
}

/// Big number, caption, status pill.
class _Header extends StatelessWidget {
  const _Header({required this.status, required this.big, required this.unit, this.caption});
  final GoalStatus status;
  final String big;
  final String unit;
  final String? caption;

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((caption ?? status.goal.name).toUpperCase(), style: Tc.caps, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(TextSpan(children: [
                TextSpan(text: big, style: Tc.title(40)),
                if (unit.isNotEmpty) TextSpan(text: ' $unit', style: Tc.label.copyWith(fontSize: 15)),
              ])),
            ),
          ]),
        ),
        const SizedBox(width: 10),
        StatusPill(status.track),
      ]);
}

class _RaceBody extends StatelessWidget {
  const _RaceBody({required this.status, required this.v});
  final GoalStatus status;
  final RaceVisual v;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final total = v.race.difference(v.blockStart).inDays.clamp(1, 10000);
    double at(DateTime d) => (d.difference(v.blockStart).inDays / total).clamp(0.0, 1.0);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Header(status: status, big: '${v.daysTo}', unit: v.daysTo == 1 ? 'day to go' : 'days to go', caption: status.goal.name),
      const SizedBox(height: 14),
      // The block: start to race day, today marked, taper shaded.
      SizedBox(
        height: 30,
        child: CustomPaint(
          size: const Size(double.infinity, 30),
          painter: _BlockPainter(today: at(now), taper: at(v.taper)),
        ),
      ),
      Row(children: [
        Text(_d(v.blockStart), style: Tc.label.copyWith(fontSize: 11)),
        const Spacer(),
        Text('Taper ${_d(v.taper)}', style: Tc.label.copyWith(fontSize: 11)),
        const SizedBox(width: 12),
        Text(_d(v.race), style: Tc.label.copyWith(fontSize: 11)),
      ]),
      const SizedBox(height: 14),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: _Mini(
            label: 'Plan, 2 weeks',
            value: v.kmShare == null ? '–' : '${(v.kmShare! * 100).round()}%',
            caption: 'of planned km',
            fill: v.kmShare?.clamp(0.0, 1.0),
            color: (v.kmShare ?? 1) >= 0.8 ? Tc.go : ((v.kmShare ?? 1) >= 0.6 ? Tc.amber : Tc.coral),
          ),
        ),
        if (v.longNeeded > 0) ...[
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Long runs', style: Tc.label.copyWith(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              Row(children: [
                for (var i = 0; i < math.max(v.longNeeded, v.longDone); i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _Dot(
                      filled: i < v.longDone,
                      planned: i >= v.longDone && i < v.longDone + v.longPlanned,
                    ),
                  ),
              ]),
              const SizedBox(height: 6),
              Text('${v.benchmarkKm.round()} km+: ${v.longDone} of ${v.longNeeded}${v.longPlanned > 0 ? ' (+${v.longPlanned} planned)' : ''}',
                  style: Tc.label.copyWith(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _Mini(
              label: 'Longest run',
              value: '${v.longestKm.round()} km',
              caption: 'of ${v.benchmarkKm.round()} km',
              fill: v.benchmarkKm == 0 ? null : (v.longestKm / v.benchmarkKm).clamp(0.0, 1.0),
              color: v.longestKm >= v.benchmarkKm ? Tc.go : Tc.amber,
            ),
          ),
        ],
      ]),
    ]);
  }
}

class _BlockPainter extends CustomPainter {
  _BlockPainter({required this.today, required this.taper});
  final double today, taper;

  @override
  void paint(Canvas canvas, Size size) {
    const h = 8.0;
    final y = size.height / 2 - h / 2;
    final track = RRect.fromRectAndRadius(Rect.fromLTWH(0, y, size.width, h), const Radius.circular(4));
    canvas.drawRRect(track, Paint()..color = Tc.muted);
    // Taper section, then the part of the block already behind you.
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.width * taper, y, size.width * (1 - taper), h), const Radius.circular(4)),
        Paint()..color = Tc.amber.withValues(alpha: 0.35));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, y, size.width * today, h), const Radius.circular(4)), Paint()..color = Tc.go);
    // Today: a marker with a 2px surface ring.
    final c = Offset(size.width * today, size.height / 2);
    canvas.drawCircle(c, 8, Paint()..color = Tc.surface);
    canvas.drawCircle(c, 6, Paint()..color = Tc.text);
  }

  @override
  bool shouldRepaint(_BlockPainter old) => old.today != today || old.taper != taper;
}

/// A long run: done (filled), planned (ring), or still missing (dim ring).
class _Dot extends StatelessWidget {
  const _Dot({required this.filled, required this.planned});
  final bool filled, planned;

  @override
  Widget build(BuildContext context) => Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled ? Tc.go : Colors.transparent,
          border: Border.all(color: filled || planned ? Tc.go : Tc.muted, width: 2),
        ),
      );
}

/// Label, value and a thin bar.
class _Mini extends StatelessWidget {
  const _Mini({required this.label, required this.value, required this.caption, required this.fill, required this.color});
  final String label, value, caption;
  final double? fill;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Tc.label.copyWith(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: Tc.title(20))),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(value: fill ?? 0, minHeight: 4, color: color, backgroundColor: Tc.muted),
        ),
        const SizedBox(height: 4),
        Text(caption, style: Tc.label.copyWith(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
      ]);
}

class _WeightBody extends StatelessWidget {
  const _WeightBody({required this.status, required this.v});
  final GoalStatus status;
  final WeightVisual v;

  @override
  Widget build(BuildContext context) {
    final span = v.start - v.target;
    final fill = span <= 0 ? 1.0 : ((v.start - v.current) / span).clamp(0.0, 1.0);
    final spark = v.spark.whereType<double>().length >= 2;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Header(status: status, big: v.current.toStringAsFixed(1), unit: 'kg → ${v.target.toStringAsFixed(1)}', caption: status.goal.name),
      const SizedBox(height: 12),
      ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: fill, minHeight: 8, color: Tc.go, backgroundColor: Tc.muted)),
      const SizedBox(height: 6),
      Row(children: [
        Text('${v.start.toStringAsFixed(1)} start', style: Tc.label.copyWith(fontSize: 11)),
        const Spacer(),
        Text(v.neededPerWeek.isFinite ? 'needs ${v.neededPerWeek.toStringAsFixed(2)} kg/week' : '', style: Tc.label.copyWith(fontSize: 11)),
      ]),
      if (spark) ...[
        const SizedBox(height: 10),
        SizedBox(height: 36, child: CustomPaint(size: const Size(double.infinity, 36), painter: _SparkPainter(v.spark))),
      ],
    ]);
  }
}

/// A small trend line with the last point marked.
class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values);
  final List<double?> values;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = <Offset>[];
    final present = values.whereType<double>();
    var lo = present.reduce(math.min), hi = present.reduce(math.max);
    if (hi - lo < 0.2) {
      lo -= 0.1;
      hi += 0.1;
    }
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) continue;
      pts.add(Offset(size.width * i / (values.length - 1), 4 + (size.height - 8) * (1 - (v - lo) / (hi - lo))));
    }
    final paint = Paint()
      ..color = Tc.go
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i < pts.length; i++) {
      canvas.drawLine(pts[i - 1], pts[i], paint);
    }
    canvas.drawCircle(pts.last, 5, Paint()..color = Tc.surface);
    canvas.drawCircle(pts.last, 3.5, Paint()..color = Tc.go);
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.values != values;
}

class _ConsistencyBody extends StatelessWidget {
  const _ConsistencyBody({required this.status, required this.v});
  final GoalStatus status;
  final ConsistencyVisual v;

  @override
  Widget build(BuildContext context) {
    Widget row(String label, int done, int target) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(children: [
            SizedBox(width: 78, child: Text(label, style: Tc.label.copyWith(fontSize: 13))),
            for (var i = 0; i < math.max(target, done); i++) Padding(padding: const EdgeInsets.only(right: 6), child: _Dot(filled: i < done, planned: false)),
            const Spacer(),
            Text('$done/$target', style: Tc.title(16)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Header(status: status, big: '${v.daysLeft}', unit: v.daysLeft == 1 ? 'day left this week' : 'days left this week', caption: status.goal.name),
      row('Runs', v.runsDone, v.runsTarget),
      row('Strength', v.strengthDone, v.strengthTarget),
    ]);
  }
}

class _AerobicBody extends StatelessWidget {
  const _AerobicBody({required this.status, required this.v});
  final GoalStatus status;
  final AerobicVisual v;

  @override
  Widget build(BuildContext context) {
    final last = v.paces.whereType<double>().lastOrNull;
    // Lower pace is better: draw it inverted so up means faster.
    final inverted = [for (final p in v.paces) p == null ? null : -p];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Header(status: status, big: last == null ? '–' : formatPace(last), unit: '/km at easy HR', caption: status.goal.name),
      if (inverted.whereType<double>().length >= 2) ...[
        const SizedBox(height: 10),
        SizedBox(height: 36, child: CustomPaint(size: const Size(double.infinity, 36), painter: _SparkPainter(inverted))),
      ],
    ]);
  }
}

/// The full reasons for one goal, for the Plan tab ("Where you stand").
class GoalCard extends StatelessWidget {
  const GoalCard({super.key, required this.status});
  final GoalStatus status;

  @override
  Widget build(BuildContext context) => TcCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(status.goal.name, style: Tc.title(18))),
            const SizedBox(width: 10),
            StatusPill(status.track),
          ]),
          const SizedBox(height: 4),
          Text(status.headline, style: Tc.body.copyWith(color: Tc.textSecondary, fontSize: 14)),
          const SizedBox(height: 10),
          for (final l in status.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Container(width: 4, height: 4, decoration: const BoxDecoration(color: Tc.textSecondary, shape: BoxShape.circle)),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(l, style: Tc.body.copyWith(fontSize: 14, height: 1.35))),
              ]),
            ),
        ]),
      );
}

/// This week so far: three bars against the plan, plus one drift flag.
class WeekStripCard extends StatelessWidget {
  const WeekStripCard({super.key, required this.w});
  final WeekStrip w;

  @override
  Widget build(BuildContext context) {
    Widget bar(String label, double done, double of, String value) => Expanded(
          child: _Mini(
            label: label,
            value: value,
            caption: of == 0 ? 'none planned' : 'of ${of % 1 == 0 ? of.round() : of.toStringAsFixed(0)} planned',
            fill: of == 0 ? null : (done / of).clamp(0.0, 1.0),
            color: Tc.go,
          ),
        );
    return TcCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          bar('Km', w.kmDone, w.kmPlanned.roundToDouble(), w.kmDone.toStringAsFixed(w.kmDone < 10 ? 1 : 0)),
          const SizedBox(width: 12),
          bar('Runs', w.runsDone.toDouble(), w.runsPlanned.toDouble(), '${w.runsDone}'),
          const SizedBox(width: 12),
          bar('Strength', w.strengthDone.toDouble(), w.strengthPlanned.toDouble(), '${w.strengthDone}'),
        ]),
        if (w.longAhead != null || w.easyRuns > 0) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (w.easyRuns > 0) _Chip(icon: Icons.favorite_border_rounded, text: 'Easy under cap ${w.easyUnder}/${w.easyRuns}'),
            if (w.longAhead != null) _Chip(icon: Icons.route_rounded, text: w.longAhead!),
          ]),
        ],
        if (w.flag != null) ...[
          const SizedBox(height: 10),
          _Chip(icon: Icons.warning_amber_rounded, text: w.flag!, color: Tc.amber),
        ],
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text, this.color = Tc.sky, this.onTap});
  final IconData icon;
  final String text;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(color: Tc.surfaceRaised, borderRadius: BorderRadius.circular(999), border: Border.all(color: Tc.hairline)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Flexible(child: Text(text, style: Tc.body.copyWith(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
        ),
      );
}

/// Insights as chips; tap one for the full sentence.
class InsightChips extends StatelessWidget {
  const InsightChips({super.key, required this.insights});
  final List<Insight> insights;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final i in insights)
          _Chip(
            icon: switch (i.kind) {
              InsightKind.hrv => Icons.monitor_heart_outlined,
              InsightKind.sleep => Icons.bedtime_outlined,
              InsightKind.restingHr => Icons.favorite_border_rounded,
              InsightKind.strength => Icons.fitness_center_rounded,
              InsightKind.tomorrow => Icons.event_outlined,
            },
            text: i.short,
            onTap: () => showModalBottomSheet<void>(
              context: context,
              backgroundColor: Tc.surface,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
              builder: (_) => SafeArea(
                child: Padding(padding: const EdgeInsets.fromLTRB(20, 24, 20, 24), child: Text(i.text, style: Tc.body.copyWith(height: 1.4))),
              ),
            ),
          ),
      ]);
}

/// Today's call in one line; tap to see the four signals behind it.
class VerdictLine extends StatelessWidget {
  const VerdictLine({super.key, required this.check, required this.isFinal, required this.open, required this.onTap});
  final MorningCheck check;
  final bool isFinal;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Tc.forVerdict(check.verdict);
    final clear = check.signals.where((s) => s.state == SignalState.clear).length;
    return Material(
      color: Tc.surface,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(28), border: Border.all(color: Tc.hairline)),
          child: Row(children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(verdictLabel(check.verdict), style: Tc.title(22).copyWith(color: color)),
                const SizedBox(height: 2),
                Text('${check.reason}${isFinal ? '' : ' · waiting for Coros sync'}', style: Tc.label.copyWith(fontSize: 13)),
              ]),
            ),
            const SizedBox(width: 8),
            Text('$clear/4', style: Tc.title(16)),
            Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: Tc.textSecondary),
          ]),
        ),
      ),
    );
  }
}
