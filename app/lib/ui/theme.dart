import 'package:flutter/material.dart';

import '../rules/morning_check.dart';

/// Colour and type tokens from the reference mockups (PRD: Visual design). Dark only in v1.
class Tc {
  static const background = Color(0xFF000000);
  static const surface = Color(0xFF101010);
  static const surfaceRaised = Color(0xFF1A1A1A);
  static const hairline = Color(0x14FFFFFF);
  static const text = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFA9AAA3);
  static const go = Color(0xFF97EB78);
  static const goButton = Color(0xFFA1F882);
  static const amber = Color(0xFFE5A438);
  static const coral = Color(0xFFEE7469);
  static const blue = Color(0xFF6496DE);
  static const sky = Color(0xFF35AAE7);
  static const muted = Color(0xFF3A3A3A);

  static const font = 'InterTight';

  static TextStyle title(double size) =>
      TextStyle(fontFamily: font, fontSize: size, fontWeight: FontWeight.w600, letterSpacing: size * -0.02, color: text, height: 1.1);
  static const label = TextStyle(fontFamily: font, fontSize: 15, color: textSecondary);
  static const body = TextStyle(fontFamily: font, fontSize: 15, color: text);
  static const caps = TextStyle(fontFamily: font, fontSize: 12, letterSpacing: 1.6, color: textSecondary, fontWeight: FontWeight.w500);

  static Color forVerdict(Verdict? v) => switch (v) {
        Verdict.goAsPlanned => go,
        Verdict.goEasy => amber,
        Verdict.rest => coral,
        _ => textSecondary,
      };

  static Color forState(SignalState s) => switch (s) {
        SignalState.clear => go,
        SignalState.flagged => amber,
        SignalState.error => coral,
        SignalState.noData => muted,
      };

  static ThemeData theme() => ThemeData(
        brightness: Brightness.dark,
        fontFamily: font,
        scaffoldBackgroundColor: background,
        colorScheme: const ColorScheme.dark(primary: go, secondary: sky, surface: surface, error: coral),
        switchTheme: SwitchThemeData(
          thumbColor: const WidgetStatePropertyAll(Colors.white),
          trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? sky : muted),
          trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surfaceRaised,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        ),
      );
}

/// Near-black card with large rounded corners and a hairline edge.
class TcCard extends StatelessWidget {
  const TcCard({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.gradient});

  final Widget child;
  final EdgeInsets padding;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: gradient == null ? Tc.surface : null,
          gradient: gradient,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Tc.hairline),
        ),
        child: child,
      );
}

/// The dashed "Nothing logged yet" card from the references, used for empty states.
class EmptyCard extends StatelessWidget {
  const EmptyCard({super.key, required this.title, required this.subtitle, this.icon = Icons.add});

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _DashedBorder(),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: Tc.surfaceRaised, borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: Tc.textSecondary, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: Tc.title(17)),
                const SizedBox(height: 4),
                Text(subtitle, style: Tc.label.copyWith(fontSize: 14)),
              ]),
            ),
          ]),
        ),
      );
}

class _DashedBorder extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x33FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(28)));
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 10) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Lime pill button from the references.
class PillButton extends StatelessWidget {
  const PillButton({super.key, required this.label, required this.onPressed, this.icon, this.busy = false});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onPressed == null ? 0.45 : 1,
        child: Material(
          color: Tc.goButton,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: busy ? null : onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                if (busy)
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                else if (icon != null)
                  Icon(icon, size: 18, color: Colors.black),
                if (busy || icon != null) const SizedBox(width: 8),
                Text(label, style: const TextStyle(fontFamily: Tc.font, fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black)),
              ]),
            ),
          ),
        ),
      );
}
