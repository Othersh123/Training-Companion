import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../coros/parsers.dart';
import '../data/food_store.dart';
import '../data/goal.dart';
import '../food/food.dart';
import '../food/ifct.dart';
import '../food/targets.dart';
import '../sync/food_day.dart';
import 'charts.dart';
import 'food_search_screen.dart';
import 'food_widgets.dart';
import 'theme.dart';

/// The Log tab (PRD F4): yesterday's or today's meals against the day-type targets, and weight.
class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogData {
  _LogData(this.day, this.weights, this.weightGoal);
  final FoodDay day;
  final Map<String, double> weights;
  final Goal? weightGoal;
}

class _LogScreenState extends State<LogScreen> {
  int _offset = 0; // 0 today, -1 yesterday
  Future<_LogData>? _future;
  int? _loadedFor;
  bool _autoRefreshed = false;

  DateTime get _date {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).add(Duration(days: _offset));
  }

  /// Stored IFCT foods are checked against the bundled table once per app start.
  static bool _ifctChecked = false;

  Future<_LogData> _load(AppController app) async {
    if (!_ifctChecked) {
      _ifctChecked = true;
      final fixed = await app.db.refreshIfctFoods((await Ifct.load()).byCode);
      if (fixed.isNotEmpty) await app.db.logError('food', 'IFCT values corrected; recipes recalculated: ${fixed.join(', ')}');
    }
    final d = _date;
    final day = await app.sync.foodDay(d);
    final weights = await app.db.weightsBetween(corosDate(d.subtract(const Duration(days: 34))), corosDate(d));
    final goal = (await app.db.goals()).where((g) => g.type == GoalType.weight).firstOrNull;
    // First open after M4: fetch the Coros profile and active-calorie history once, unasked.
    if (day.missingProfile != null && app.signedIn && !_autoRefreshed) {
      _autoRefreshed = true;
      app.refreshFood();
    }
    return _LogData(day, weights, goal);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final key = app.foodRevision * 10 + _offset + 1;
    if (_future == null || _loadedFor != key) {
      _loadedFor = key;
      _future = app.screenLoad('Log', () => _load(app));
    }
    return RefreshIndicator(
      color: Tc.go,
      backgroundColor: Tc.surface,
      onRefresh: app.refreshFood,
      child: FutureBuilder<_LogData>(
        future: _future,
        builder: (context, snap) {
          final data = snap.data;
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Expanded(child: Text(_offset == 0 ? 'Today\'s meals' : 'Yesterday\'s meals', style: Tc.title(30))),
                const SizedBox(width: 12),
                PillButton(label: 'Add', icon: Icons.add_rounded, onPressed: () => openFoodSearch(context, _date, guessMeal(DateTime.now()))),
              ]),
              const SizedBox(height: 18),
              Segmented<int>(values: const [-1, 0], labels: const ['Yesterday', 'Today'], selected: _offset, onChanged: (v) => setState(() => _offset = v)),
              const SizedBox(height: 16),
              if (snap.hasError)
                EmptyCard(icon: Icons.error_outline, title: 'Couldn\'t load this day', subtitle: '${snap.error}')
              else if (data == null)
                const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: Tc.go)))
              else ...[
                _TargetsCard(day: data.day),
                for (final m in Meal.values) _MealSection(day: data.day, meal: m),
                const SizedBox(height: 8),
                _WeightCard(date: _date, todayWeight: data.day.weight, weights: data.weights, goal: data.weightGoal),
                const SizedBox(height: 16),
                Text('Targets are estimates from general sports nutrition guidance, not medical or dietetic advice. Edit them in Settings.',
                    style: Tc.label.copyWith(fontSize: 12, height: 1.4)),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Breakfast before 11, lunch before 16, snacks before 19, then dinner.
Meal guessMeal(DateTime t) => t.hour < 11
    ? Meal.breakfast
    : t.hour < 16
        ? Meal.lunch
        : t.hour < 19
            ? Meal.snacks
            : Meal.dinner;

class _TargetsCard extends StatelessWidget {
  const _TargetsCard({required this.day});
  final FoodDay day;

  @override
  Widget build(BuildContext context) {
    final t = day.targets;
    final eaten = day.totals;
    if (t == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: EmptyCard(
          icon: Icons.person_outline_rounded,
          title: 'Targets need your Coros profile',
          subtitle: 'Missing: ${day.missingProfile}. Pull down to fetch it from Coros.',
        ),
      );
    }
    final left = t.kcal - eaten.kcal;
    return GestureDetector(
      onTap: () => _explain(context, t),
      child: TcCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(t.dayType.type.label.toUpperCase(), style: Tc.caps, maxLines: 1, overflow: TextOverflow.ellipsis)),
            const _EstimateTag(),
          ]),
          const SizedBox(height: 4),
          Text(t.dayType.reason, style: Tc.label.copyWith(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 14),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(thousands(left.abs()), style: Tc.title(44)),
              ),
            ),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(left >= 0 ? 'kcal left' : 'kcal over', style: Tc.label),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('${thousands(eaten.kcal)} / ${thousands(t.kcal)}', style: Tc.label.copyWith(fontSize: 13)),
            ),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: t.kcal == 0 ? 0 : (eaten.kcal / t.kcal).clamp(0, 1),
              minHeight: 6,
              color: Tc.go,
              backgroundColor: Tc.muted,
            ),
          ),
          const SizedBox(height: 14),
          // Two by two: four tiles in a row truncate "Protein" at large text on a 360dp phone.
          Row(children: [
            Expanded(child: MacroTile(label: 'Protein', color: MacroColors.protein, eaten: eaten.protein, target: t.protein)),
            const SizedBox(width: 8),
            Expanded(child: MacroTile(label: 'Carbs', color: MacroColors.carbs, eaten: eaten.carbs, target: t.carbs)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: MacroTile(label: 'Fat', color: MacroColors.fat, eaten: eaten.fat, target: t.fat)),
            const SizedBox(width: 8),
            Expanded(child: MacroTile(label: 'Fibre', color: MacroColors.fibre, eaten: eaten.fibre, target: t.fibre)),
          ]),
          if (t.deficitNote != null) ...[
            const SizedBox(height: 12),
            Text(t.deficitNote!, style: Tc.label.copyWith(fontSize: 13, height: 1.35)),
          ],
        ]),
      ),
    );
  }

  void _explain(BuildContext context, FoodTargets t) => showModalBottomSheet<void>(
        context: context,
        backgroundColor: Tc.surface,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        builder: (ctx) {
          Widget row(String a, String b) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [Expanded(child: Text(a, style: Tc.label)), Text(b, style: Tc.body)]),
              );
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('How today\'s targets are set', style: Tc.title(20)),
                const SizedBox(height: 14),
                row('Resting energy (Mifflin-St Jeor)', '${thousands(t.restingKcal)} kcal'),
                row('Active calories (Coros)', '+${thousands(t.activeKcal)} kcal'),
                if (t.deficit > 0) row('Weight goal', '−${thousands(t.deficit)} kcal'),
                row('Target', '${thousands(t.kcal)} kcal'),
                const Divider(color: Tc.hairline, height: 24),
                row('Protein', '${t.protein.round()} g'),
                row('Carbs (${t.dayType.type.label.toLowerCase()})', '${t.carbs.round()} g'),
                row('Fat (the rest, at least 20%)', '${t.fat.round()} g'),
                row('Fibre (14 g per 1,000 kcal)', '${t.fibre.round()} g'),
                const SizedBox(height: 12),
                Text(
                  'Day type: ${t.dayType.reason}. Carbs and protein are grams per kg of body weight, from the 2016 sports nutrition position '
                  'of the American College of Sports Medicine, the Academy of Nutrition and Dietetics and Dietitians of Canada. '
                  'For today, active calories are what Coros has so far or your usual for this kind of day, whichever is higher.\n\n'
                  'These are estimates and general guidance, not medical or dietetic advice.',
                  style: Tc.label.copyWith(fontSize: 13, height: 1.4),
                ),
              ]),
            ),
          );
        },
      );
}

class _EstimateTag extends StatelessWidget {
  const _EstimateTag();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: Tc.hairline)),
        child: Text('Estimate', style: Tc.label.copyWith(fontSize: 11)),
      );
}

class _MealSection extends StatelessWidget {
  const _MealSection({required this.day, required this.meal});
  final FoodDay day;
  final Meal meal;

  @override
  Widget build(BuildContext context) {
    final entries = day.entriesFor(meal);
    final kcal = Nutrients.sum(entries.map((e) => e.nutrients)).kcal;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 0, 10),
        child: Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: mealColor(meal), shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(child: Text(meal.label, style: Tc.title(19))),
          Text('${thousands(kcal)} kcal', style: Tc.label.copyWith(fontSize: 14)),
          if (entries.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz_rounded, color: Tc.textSecondary, size: 20),
              color: Tc.surfaceRaised,
              tooltip: '${meal.label} options',
              onSelected: (v) => v == 'add' ? openFoodSearch(context, day.date, meal) : _saveAsMeal(context, entries),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'add', child: Text('Add food')),
                PopupMenuItem(value: 'save', child: Text('Save as a meal')),
              ],
            )
          else
            const SizedBox(width: 12),
        ]),
      ),
      if (entries.isEmpty)
        InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: () => openFoodSearch(context, day.date, meal),
          child: EmptyCard(title: 'Nothing logged yet', subtitle: 'Tap to add ${meal == Meal.runFuel ? 'gels, drinks or snacks around a run' : meal.label.toLowerCase()}.'),
        )
      else
        for (final e in entries) Padding(padding: const EdgeInsets.only(bottom: 8), child: _EntryCard(entry: e)),
    ]);
  }

  Future<void> _saveAsMeal(BuildContext context, List<MealEntry> entries) async {
    final app = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController(text: 'My ${meal.label.toLowerCase()}');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Tc.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text('Save as a meal', style: Tc.title(20)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Log these ${entries.length} items again in one tap from Add.', style: Tc.label.copyWith(fontSize: 14)),
          const SizedBox(height: 14),
          TextField(controller: controller, autofocus: true, style: Tc.body),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Tc.textSecondary))),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Save', style: TextStyle(color: Tc.go))),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final items = <SavedMealItem>[];
    for (final e in entries) {
      final known = e.foodId == null ? null : await app.db.foodById(e.foodId!);
      // A typed-in entry becomes a food of its own (hidden from search), so the meal can
      // log it again with the same values (owner, 5 Oct 2026).
      final food = known ??
          Food(
            source: FoodSource.manual,
            name: e.name,
            per100g: e.grams == 0 ? e.nutrients : e.nutrients.scale(100 / e.grams),
            servingGrams: e.servingGrams,
            servingName: e.servingGrams == null ? null : 'serving',
          );
      items.add(SavedMealItem(food: food, grams: e.grams == 0 ? 100 : e.grams));
    }
    await app.db.saveSavedMeal(SavedMeal(name: name, items: items));
    app.foodChanged();
    messenger.showSnackBar(SnackBar(content: Text('Saved "$name". Find it under Saved meals in Add.')));
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry});
  final MealEntry entry;

  double get _step => entry.servingGrams ?? (entry.grams >= 50 ? 25 : 10);

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    Future<void> setGrams(double g) async {
      // Taken before the list reloads: this row is gone afterwards.
      final messenger = ScaffoldMessenger.of(context);
      await app.db.setEntryGrams(entry, g);
      app.foodChanged();
      if (g <= 0) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(SnackBar(
          content: Text('Removed ${entry.name}'),
          // A snackbar with an action stays until tapped unless told otherwise (5 Oct 2026).
          persist: false,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(label: 'Undo', onPressed: () async {
            await app.db.addEntry(entry);
            app.foodChanged();
          }),
        ));
      }
    }

    return Material(
      color: Tc.surface,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => _edit(context, setGrams),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), border: Border.all(color: Tc.hairline)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(entry.name, style: Tc.body.copyWith(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Text(amountLabel(entry.grams, entry.servingGrams), style: Tc.label.copyWith(fontSize: 13)),
                const SizedBox(height: 6),
                MacroChips(entry.nutrients),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(thousands(entry.nutrients.kcal), style: Tc.title(18)),
              const SizedBox(height: 12),
              AmountStepper(
                label: entry.servingGrams != null ? amountLabel(entry.grams, entry.servingGrams).split(' ').first : '',
                onMinus: () => setGrams((entry.grams - _step).clamp(0, double.infinity)),
                onPlus: () => setGrams(entry.grams + _step),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, Future<void> Function(double) setGrams) async {
    final serving = entry.servingGrams;
    final controller = TextEditingController(
        text: serving != null ? amountLabel(entry.grams, serving).split(' ').first : entry.grams.round().toString());
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Tc.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text(entry.name, style: Tc.title(20)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: Tc.title(22),
          decoration: InputDecoration(suffixText: serving != null ? 'servings' : 'g'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 0.0), child: const Text('Remove', style: TextStyle(color: Tc.coral))),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Tc.textSecondary))),
          TextButton(
            onPressed: () {
              final v = double.tryParse(controller.text.trim());
              if (v != null && v >= 0) Navigator.pop(ctx, serving != null ? v * serving : v);
            },
            child: const Text('Save', style: TextStyle(color: Tc.go)),
          ),
        ],
      ),
    );
    if (result != null) await setGrams(result);
  }
}

class _WeightCard extends StatelessWidget {
  const _WeightCard({required this.date, required this.todayWeight, required this.weights, required this.goal});
  final DateTime date;
  final double? todayWeight;
  final Map<String, double> weights;
  final Goal? goal;

  @override
  Widget build(BuildContext context) {
    final avg = sevenDayAverage(weights, date);
    final weekAgo = sevenDayAverage(weights, date.subtract(const Duration(days: 7)));
    final days = [for (var i = 27; i >= 0; i--) date.subtract(Duration(days: i))];
    final trend = [for (final d in days) weights.isEmpty ? null : sevenDayAverage(weights, d)];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    String label(DateTime d) => '${d.day} ${months[d.month - 1]}';

    return TcCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Weight', style: Tc.title(19))),
          if (avg != null && weekAgo != null)
            Text('${avg - weekAgo >= 0 ? '+' : '−'}${(avg - weekAgo).abs().toStringAsFixed(1)} kg in 7 days', style: Tc.label.copyWith(fontSize: 13)),
        ]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(avg == null ? '–' : avg.toStringAsFixed(1), style: Tc.title(32)),
          const SizedBox(width: 6),
          Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('kg, 7-day average', style: Tc.label.copyWith(fontSize: 13))),
        ]),
        const SizedBox(height: 4),
        Text(
          [
            todayWeight == null ? 'Not logged ${_isToday ? 'today' : 'this day'}' : '${todayWeight!.toStringAsFixed(1)} kg ${_isToday ? 'today' : 'this day'}',
            if (goal?.targetWeightKg != null && goal?.date != null) 'goal ${goal!.targetWeightKg!.toStringAsFixed(1)} kg by ${label(goal!.date!)}',
          ].join(' · '),
          style: Tc.label.copyWith(fontSize: 13),
        ),
        if (trend.whereType<double>().length >= 2) ...[
          const SizedBox(height: 12),
          TrendLine(values: trend, labels: [for (final d in days) label(d)], format: (v) => '${v.toStringAsFixed(1)} kg', height: 90),
        ],
        const SizedBox(height: 14),
        PillButton(
          label: todayWeight == null ? 'Log weight' : 'Edit weight',
          icon: Icons.monitor_weight_outlined,
          onPressed: () => showWeightSheet(context, date, todayWeight),
        ),
      ]),
    );
  }

  bool get _isToday {
    final n = DateTime.now();
    return date.year == n.year && date.month == n.month && date.day == n.day;
  }
}

/// Morning weight, entered by hand (PRD F4: the owner's scale has no app).
Future<void> showWeightSheet(BuildContext context, DateTime day, double? current) async {
  final app = AppScope.of(context);
  final controller = TextEditingController(text: current?.toStringAsFixed(1) ?? '');
  String? error;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Tc.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => Padding(
        padding: EdgeInsets.fromLTRB(20, 24, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Morning weight', style: Tc.title(22)),
          const SizedBox(height: 6),
          Text('Weigh after waking, before eating. The trend uses a 7-day average, so daily swings don\'t mislead.',
              style: Tc.label.copyWith(fontSize: 13, height: 1.4)),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: Tc.title(28),
            decoration: InputDecoration(suffixText: 'kg', errorText: error),
          ),
          const SizedBox(height: 16),
          Row(children: [
            if (current != null)
              TextButton(
                onPressed: () async {
                  await app.deleteWeight(day);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Delete', style: TextStyle(color: Tc.coral)),
              ),
            const Spacer(),
            PillButton(
              label: 'Save',
              onPressed: () async {
                final kg = double.tryParse(controller.text.trim().replaceAll(',', '.'));
                if (kg == null || kg < 25 || kg > 300) {
                  setSheet(() => error = 'Enter your weight in kg, e.g. 78.4');
                  return;
                }
                await app.saveWeight(day, kg);
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
          ]),
        ]),
      ),
    ),
  );
}
