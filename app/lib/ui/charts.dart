import 'package:flutter/material.dart';

import 'theme.dart';

/// One bar. [flagged] bars are drawn amber and always carry a text label as well
/// (amber is never the only signal; see the dataviz check in learnings).
class BarDatum {
  BarDatum({required this.label, required this.value, required this.tooltip, this.flagged = false, this.valueLabel});
  final String label;
  final double value;
  final String tooltip;
  final bool flagged;

  /// Shown above the bar; null for no label (zero days stay unlabelled).
  final String? valueLabel;
}

/// Single-series bar chart in the reference style: rounded data-ends anchored to the
/// baseline, 2px gaps, recessive axis, text in text colours. Tap a bar for its tooltip.
class BarChart extends StatefulWidget {
  const BarChart({super.key, required this.data, this.height = 150});
  final List<BarDatum> data;
  final double height;

  @override
  State<BarChart> createState() => _BarChartState();
}

class _BarChartState extends State<BarChart> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final maxV = widget.data.fold(0.0, (m, d) => d.value > m ? d.value : m);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: 20,
        child: _selected == null
            ? null
            : Text(widget.data[_selected!].tooltip, style: Tc.body.copyWith(fontSize: 13, color: Tc.text)),
      ),
      const SizedBox(height: 6),
      LayoutBuilder(builder: (context, c) {
        final slot = c.maxWidth / widget.data.length;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => setState(() {
            final i = (d.localPosition.dx / slot).floor().clamp(0, widget.data.length - 1);
            _selected = _selected == i ? null : i;
          }),
          child: SizedBox(
            height: widget.height,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (final (i, d) in widget.data.indexed)
                Expanded(
                  child: Column(children: [
                    // The bar area takes whatever height the day letter leaves, and sizes the
                    // value label from the phone's font scale, so nothing can overflow at any
                    // font size (fixed pixel heights overflowed by 1px on 3 Oct 2026).
                    Expanded(
                      child: LayoutBuilder(builder: (context, area) {
                        final labelSpace = MediaQuery.textScalerOf(context).scale(11) * 1.5 + 4;
                        final barMax = (area.maxHeight - labelSpace).clamp(0.0, double.infinity);
                        final barHeight = maxV == 0 ? 3.0 : (d.value / maxV * barMax).clamp(d.value > 0 ? 6.0 : 3.0, barMax);
                        return Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                          if (d.valueLabel != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(d.valueLabel!, maxLines: 1, style: Tc.label.copyWith(fontSize: 11)),
                            ),
                          Container(
                            height: barHeight,
                            margin: const EdgeInsets.symmetric(horizontal: 3), // the 2px+ surface gap
                            decoration: BoxDecoration(
                              // A flagged day with no running still shows an amber stub.
                              color: (d.flagged ? Tc.amber : (d.value == 0 ? Tc.muted : Tc.go))
                                  .withValues(alpha: _selected == null || _selected == i ? 1 : 0.45),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(4), bottom: Radius.circular(2)),
                            ),
                          ),
                        ]);
                      }),
                    ),
                    const SizedBox(height: 8),
                    Text(d.label, maxLines: 1, style: Tc.label.copyWith(fontSize: 12, color: _selected == i ? Tc.text : Tc.textSecondary)),
                  ]),
                ),
            ]),
          ),
        );
      }),
    ]);
  }
}

/// A 12-week trend: 2px line, 8px markers, gaps where a week has no value, tap for a tooltip.
class TrendLine extends StatefulWidget {
  const TrendLine({super.key, required this.values, required this.labels, required this.format, this.height = 140, this.markEstimated});
  final List<double?> values;
  final List<String> labels;
  final String Function(double) format;
  final double height;

  /// Weeks whose value is an estimate get a hollow marker.
  final List<bool>? markEstimated;

  @override
  State<TrendLine> createState() => _TrendLineState();
}

class _TrendLineState extends State<TrendLine> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final sel = _selected;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: 20,
        child: sel == null
            ? null
            : Text(
                '${widget.labels[sel]}: ${widget.values[sel] == null ? 'no data' : widget.format(widget.values[sel]!)}'
                '${(widget.markEstimated?[sel] ?? false) ? ' (estimated)' : ''}',
                style: Tc.body.copyWith(fontSize: 13)),
      ),
      const SizedBox(height: 6),
      LayoutBuilder(builder: (context, c) {
        final slot = c.maxWidth / widget.values.length;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => setState(() {
            final i = (d.localPosition.dx / slot).floor().clamp(0, widget.values.length - 1);
            _selected = _selected == i ? null : i;
          }),
          child: CustomPaint(
            size: Size(c.maxWidth, widget.height),
            painter: _TrendPainter(widget.values, widget.markEstimated, sel),
          ),
        );
      }),
      const SizedBox(height: 6),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(widget.labels.first, style: Tc.label.copyWith(fontSize: 11)),
        Text(widget.labels.last, style: Tc.label.copyWith(fontSize: 11)),
      ]),
    ]);
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.values, this.estimated, this.selected);
  final List<double?> values;
  final List<bool>? estimated;
  final int? selected;

  @override
  void paint(Canvas canvas, Size size) {
    final present = values.whereType<double>().toList();
    final grid = Paint()
      ..color = Tc.hairline
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final y = 8 + (size.height - 16) * i / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (present.isEmpty) return;
    var lo = present.reduce((a, b) => a < b ? a : b), hi = present.reduce((a, b) => a > b ? a : b);
    if (hi - lo < 1e-9) {
      lo -= 1;
      hi += 1;
    }
    final slot = size.width / values.length;
    Offset? at(int i) => values[i] == null ? null : Offset(slot * (i + 0.5), 8 + (size.height - 16) * (1 - (values[i]! - lo) / (hi - lo)));

    final line = Paint()
      ..color = Tc.go
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i < values.length; i++) {
      final a = at(i - 1), b = at(i);
      if (a != null && b != null) canvas.drawLine(a, b, line);
    }
    if (selected != null && at(selected!) != null) {
      canvas.drawLine(Offset(at(selected!)!.dx, 0), Offset(at(selected!)!.dx, size.height), grid..color = const Color(0x33FFFFFF));
    }
    for (var i = 0; i < values.length; i++) {
      final p = at(i);
      if (p == null) continue;
      final hollow = estimated?[i] ?? false;
      canvas.drawCircle(p, 5, Paint()..color = Tc.surface); // 2px surface ring
      canvas.drawCircle(
          p,
          4,
          Paint()
            ..color = Tc.go
            ..style = hollow ? PaintingStyle.stroke : PaintingStyle.fill
            ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) => old.values != values || old.selected != selected;
}
