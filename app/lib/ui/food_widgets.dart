import 'package:flutter/material.dart';

import '../food/food.dart';
import 'theme.dart';

/// Macro colours from the PRD: protein coral, carbs amber, fat blue. Always shown with a
/// letter or a label, never colour alone.
class MacroColors {
  static const protein = Tc.coral;
  static const carbs = Tc.amber;
  static const fat = Tc.blue;

  /// Teal, as the reference meal list's "8 fibre" chip; sky would sit too close to fat's blue.
  static const fibre = Color(0xFF3EC1B0);
}

/// Meal section dots (identity only; each sits next to its label).
Color mealColor(Meal m) => switch (m) {
      Meal.breakfast => Tc.amber,
      Meal.lunch => Tc.coral,
      Meal.dinner => Tc.blue,
      Meal.snacks => Tc.sky,
      Meal.runFuel => Tc.go,
    };

/// "14P 52C 9F" chips from the reference meal list.
class MacroChips extends StatelessWidget {
  const MacroChips(this.n, {super.key, this.size = 13});
  final Nutrients n;
  final double size;

  @override
  Widget build(BuildContext context) {
    TextSpan part(String v, Color c) => TextSpan(text: '$v  ', style: TextStyle(color: c, fontWeight: FontWeight.w600));
    return Text.rich(
      TextSpan(style: TextStyle(fontFamily: Tc.font, fontSize: size), children: [
        part('${grams(n.protein)}P', MacroColors.protein),
        part('${grams(n.carbs)}C', MacroColors.carbs),
        part('${grams(n.fat)}F', MacroColors.fat),
      ]),
      maxLines: 1,
      overflow: TextOverflow.fade,
      softWrap: false,
    );
  }
}

/// Protein, carbs or fat against target, with a thin progress bar (reference home tiles).
class MacroTile extends StatelessWidget {
  const MacroTile({super.key, required this.label, required this.color, required this.eaten, required this.target});
  final String label;
  final Color color;
  final double eaten;
  final double? target;

  @override
  Widget build(BuildContext context) {
    final t = target;
    final over = t != null && eaten > t * 1.1;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(color: Tc.surfaceRaised, borderRadius: BorderRadius.circular(20), border: Border.all(color: Tc.hairline)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Flexible(child: Text(label, style: Tc.label.copyWith(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(TextSpan(children: [
            TextSpan(text: eaten.round().toString(), style: Tc.title(22)),
            if (t != null) TextSpan(text: ' / ${t.round()}g', style: Tc.label.copyWith(fontSize: 13)),
          ])),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: t == null || t == 0 ? 0 : (eaten / t).clamp(0, 1),
            minHeight: 4,
            color: color,
            backgroundColor: Tc.muted,
          ),
        ),
        if (over) ...[const SizedBox(height: 6), Text('Over target', style: Tc.label.copyWith(fontSize: 11))],
      ]),
    );
  }
}

/// The small "− 1 +" stepper from the reference meal rows.
class AmountStepper extends StatelessWidget {
  const AmountStepper({super.key, required this.label, required this.onMinus, required this.onPlus});
  final String label;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        _StepButton(icon: Icons.remove_rounded, onTap: onMinus, semantic: 'Less'),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 34),
          child: Text(label, textAlign: TextAlign.center, style: Tc.body.copyWith(fontSize: 14)),
        ),
        _StepButton(icon: Icons.add_rounded, onTap: onPlus, semantic: 'More', accent: true),
      ]);
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap, required this.semantic, this.accent = false});
  final IconData icon;
  final VoidCallback onTap;
  final String semantic;
  final bool accent;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: semantic,
        child: Material(
          color: accent ? const Color(0xFF1C2A17) : Tc.muted.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: SizedBox(width: 32, height: 32, child: Icon(icon, size: 18, color: accent ? Tc.go : Tc.text)),
          ),
        ),
      );
}

/// "60 g", "2 servings", "1.5 servings".
String amountLabel(double grams, double? servingGrams) {
  if (servingGrams == null || servingGrams <= 0) return '${grams.round()} g';
  final s = grams / servingGrams;
  final text = s == s.roundToDouble() ? s.round().toString() : s.toStringAsFixed(1);
  return '$text serving${s == 1 ? '' : 's'}';
}

/// Round back-arrow button used at the top of pushed screens.
class BackSquare extends StatelessWidget {
  const BackSquare({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Back',
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: Tc.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: Tc.hairline)),
            child: const Icon(Icons.arrow_back_rounded, color: Tc.text, size: 20),
          ),
        ),
      );
}

/// A rounded segmented control (reference "Yesterday / Today / Tomorrow").
class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.values, required this.labels, required this.selected, required this.onChanged});
  final List<T> values;
  final List<String> labels;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: Tc.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: Tc.hairline)),
        child: Row(children: [
          for (final (i, v) in values.indexed)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(v),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(color: v == selected ? Tc.surfaceRaised : Colors.transparent, borderRadius: BorderRadius.circular(14)),
                  child: Text(labels[i],
                      textAlign: TextAlign.center,
                      style: Tc.body.copyWith(color: v == selected ? Tc.text : Tc.textSecondary, fontWeight: v == selected ? FontWeight.w600 : FontWeight.w400)),
                ),
              ),
            ),
        ]),
      );
}

/// 2930 -> "2,930".
String thousands(double v) {
  final s = v.round().abs().toString();
  final out = s.length <= 3 ? s : '${s.substring(0, s.length - 3)},${s.substring(s.length - 3)}';
  return v.round() < 0 ? '-$out' : out;
}
