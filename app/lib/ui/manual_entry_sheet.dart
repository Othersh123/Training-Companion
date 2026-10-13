import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../coros/parsers.dart';
import '../data/food_store.dart';
import '../food/fndds.dart';
import '../food/food.dart';
import 'food_widgets.dart';
import 'theme.dart';

/// A one-off entry typed in by hand (a restaurant meal, a fruit). Not saved as a food.
/// Matching USDA foods are offered as estimates with household portions, one per part of
/// the name, so "rice + chapati" adds up both (owner, 5 Oct 2026).
Future<bool?> showManualEntry(BuildContext context, DateTime date, Meal meal, {String initialName = ''}) => showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Tc.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => ManualEntrySheet(date: date, meal: meal, initialName: initialName),
    );

class _Pick {
  _Pick(this.food, this.portion, this.count);
  final FnddsFood food;
  final (String, double) portion;
  final double count;

  Nutrients get nutrients => food.per100g.scale(portion.$2 * count / 100);
  String get countLabel => count == count.roundToDouble() ? count.round().toString() : count.toStringAsFixed(1);
}

class ManualEntrySheet extends StatefulWidget {
  const ManualEntrySheet({super.key, required this.date, required this.meal, this.initialName = ''});
  final DateTime date;
  final Meal meal;
  final String initialName;

  @override
  State<ManualEntrySheet> createState() => _ManualEntrySheetState();
}

class _ManualEntrySheetState extends State<ManualEntrySheet> {
  late final _name = TextEditingController(text: widget.initialName);
  final _kcal = TextEditingController(), _p = TextEditingController(), _c = TextEditingController(), _f = TextEditingController();
  Fndds? _fndds;

  /// Each part of the name ("rice", "chapati") with its matches and the estimate picked.
  List<String> _parts = [];
  final _matches = <String, List<FnddsFood>>{};
  final _picks = <String, _Pick>{};

  /// The numbers were typed or changed by hand: estimates no longer overwrite them.
  bool _edited = false;
  String? _error;
  bool _warned = false;

  @override
  void initState() {
    super.initState();
    Fndds.load().then((f) {
      if (!mounted) return;
      _fndds = f;
      _search();
    });
  }

  void _search() {
    final f = _fndds;
    final parts = f == null ? <String>[] : Fndds.parts(_name.text);
    setState(() {
      _parts = parts;
      _matches
        ..clear()
        ..addAll({for (final p in parts) p: f!.search(p, limit: 4)});
      final before = _picks.length;
      _picks.removeWhere((part, _) => !parts.contains(part));
      if (_picks.length != before) _fill();
    });
  }

  void _pick(String part, _Pick? pick) {
    setState(() {
      if (pick == null) {
        _picks.remove(part);
      } else {
        _picks[part] = pick;
      }
      _edited = false;
      _fill();
    });
  }

  /// Fills the fields with the sum of the picked estimates.
  void _fill() {
    _warned = false;
    _error = null;
    if (_edited) return;
    final n = Nutrients.sum(_picks.values.map((p) => p.nutrients));
    String r(double v) => v < 10 ? v.toStringAsFixed(1) : v.round().toString();
    final any = _picks.isNotEmpty;
    _kcal.text = any ? n.kcal.round().toString() : '';
    _p.text = any ? r(n.protein) : '';
    _c.text = any ? r(n.carbs) : '';
    _f.text = any ? r(n.fat) : '';
  }

  double? _v(TextEditingController t) => double.tryParse(t.text.trim().replaceAll(',', '.'));

  Future<void> _log() async {
    final values = [_v(_kcal), _v(_p), _v(_c), _v(_f)];
    if (_name.text.trim().isEmpty || values.any((x) => x == null || x < 0)) {
      setState(() => _error = 'Enter a name, and calories, protein, carbs and fat (0 if none). Pick an estimate if you don\'t know them.');
      return;
    }
    final [kcal, p, c, f] = values.cast<double>();
    if (!_warned && macrosDisagree(kcal, p, c, f)) {
      setState(() {
        _warned = true;
        _error = 'These macros add up to about ${thousands(kcalFromMacros(p, c, f))} kcal, not ${thousands(kcal)}. '
            'Check them, or tap Log it again to keep them.';
      });
      return;
    }
    final app = AppScope.of(context);
    final fibre = _edited ? 0.0 : Nutrients.sum(_picks.values.map((p) => p.nutrients)).fibre;
    await app.db.addEntry(MealEntry(
      date: corosDate(widget.date),
      meal: widget.meal,
      name: _name.text.trim(),
      // One serving of whatever was typed, so the stepper can scale it.
      grams: 1,
      servingGrams: 1,
      nutrients: Nutrients(kcal: kcal, protein: p, carbs: c, fat: f, fibre: fibre),
    ));
    if (mounted) Navigator.pop(context, true);
  }

  Widget _chip(String label, bool selected, VoidCallback onTap, {Color background = Tc.surfaceRaised, double size = 13}) => ChoiceChip(
        label: Text(label, overflow: TextOverflow.ellipsis),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: Tc.goButton,
        backgroundColor: background,
        labelStyle: TextStyle(fontFamily: Tc.font, fontSize: size, color: selected ? Colors.black : Tc.text),
        showCheckmark: false,
        side: const BorderSide(color: Tc.hairline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      );

  Widget _part(String part) {
    final matches = _matches[part] ?? const [];
    final pick = _picks[part];
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_parts.length == 1 ? 'ESTIMATE FROM' : 'ESTIMATE FOR "${part.toUpperCase()}"', style: Tc.caps),
        const SizedBox(height: 8),
        if (matches.isEmpty)
          Text('No match. Type the numbers, or try another word.', style: Tc.label.copyWith(fontSize: 13))
        else
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final m in matches)
              _chip(m.name, pick?.food == m, () => _pick(part, pick?.food == m ? null : _Pick(m, m.defaultPortion, 1))),
          ]),
        if (pick != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Tc.surfaceRaised, borderRadius: BorderRadius.circular(20), border: Border.all(color: Tc.hairline)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('How much? ${thousands(pick.nutrients.kcal)} kcal', style: Tc.body.copyWith(fontWeight: FontWeight.w500))),
                AmountStepper(
                  label: pick.countLabel,
                  onMinus: () => _pick(part, _Pick(pick.food, pick.portion, (pick.count - 0.5).clamp(0.5, 20))),
                  onPlus: () => _pick(part, _Pick(pick.food, pick.portion, (pick.count + 0.5).clamp(0.5, 20))),
                ),
              ]),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final p in [...pick.food.portions, ('100 g', 100.0)])
                  _chip('${p.$1} · ${p.$2.round()} g', pick.portion == p, () => _pick(part, _Pick(pick.food, p, pick.count)), background: Tc.surface, size: 12),
              ]),
            ]),
          ),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget num(TextEditingController t, String label, String suffix) => Expanded(
          child: TextField(
            controller: t,
            onChanged: (_) => setState(() {
              _edited = true;
              _warned = false;
              _error = null;
            }),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: Tc.body,
            decoration: InputDecoration(labelText: label, labelStyle: Tc.label.copyWith(fontSize: 13), suffixText: suffix),
          ),
        );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Enter manually', style: Tc.title(22)),
            const SizedBox(height: 6),
            Text('For ${widget.meal.label.toLowerCase()}. Don\'t know the numbers? Pick an estimate for each item.', style: Tc.label.copyWith(fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              onChanged: (_) => _search(),
              style: Tc.body,
              decoration: InputDecoration(labelText: 'What you ate', hintText: 'e.g. guava, or rice + chapati', labelStyle: Tc.label.copyWith(fontSize: 13)),
            ),
            for (final part in _parts) _part(part),
            if (_picks.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                _edited
                    ? 'You\'ve changed the numbers; the estimates no longer fill them in.'
                    : 'Estimates from USDA survey foods: US recipes and portions, so treat them as a rough guide.',
                style: Tc.label.copyWith(fontSize: 12, height: 1.35),
              ),
            ],
            const SizedBox(height: 14),
            Row(children: [num(_kcal, 'Calories', 'kcal'), const SizedBox(width: 8), num(_p, 'Protein', 'g')]),
            const SizedBox(height: 10),
            Row(children: [num(_c, 'Carbs', 'g'), const SizedBox(width: 8), num(_f, 'Fat', 'g')]),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: Tc.label.copyWith(color: Tc.coral, fontSize: 13))),
            const SizedBox(height: 16),
            Align(alignment: Alignment.centerRight, child: PillButton(label: 'Log it', onPressed: _log)),
          ]),
        ),
      ),
    );
  }
}
