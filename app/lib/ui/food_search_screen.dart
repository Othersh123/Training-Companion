import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../coros/parsers.dart';
import '../data/food_store.dart';
import '../food/fndds.dart';
import '../food/food.dart';
import '../food/ifct.dart';
import '../food/open_food_facts.dart';
import 'food_widgets.dart';
import 'manual_entry_sheet.dart';
import 'recipe_screen.dart';
import 'theme.dart';

Future<void> openFoodSearch(BuildContext context, DateTime date, Meal meal) =>
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => FoodSearchScreen(date: date, meal: meal)));

/// Picks a food and an amount for a recipe ingredient.
Future<RecipeItem?> pickIngredient(BuildContext context) =>
    Navigator.push<RecipeItem>(context, MaterialPageRoute(builder: (_) => const FoodSearchScreen(pick: true)));

enum _Filter { all, usda, ifct, packaged, recipes }

/// Food search (reference ref_3): chips for All, IFCT, Packaged and My recipes.
class FoodSearchScreen extends StatefulWidget {
  const FoodSearchScreen({super.key, this.date, this.meal, this.pick = false});
  final DateTime? date;
  final Meal? meal;

  /// Recipe builder mode: returns a [RecipeItem] instead of logging.
  final bool pick;

  @override
  State<FoodSearchScreen> createState() => _FoodSearchScreenState();
}

class _FoodSearchScreenState extends State<FoodSearchScreen> {
  final _query = TextEditingController();
  _Filter _filter = _Filter.all;
  Ifct? _ifct;
  Fndds? _fndds;
  List<Food> _recent = [], _recipes = [];
  List<SavedMeal> _saved = [];

  Timer? _debounce;
  String? _packagedFor;
  List<Food>? _packaged;
  String? _packagedError;
  bool _packagedBusy = false;
  final _off = OpenFoodFacts();

  @override
  void initState() {
    super.initState();
    Ifct.load().then((v) => mounted ? setState(() => _ifct = v) : null);
    Fndds.load().then((v) => mounted ? setState(() => _fndds = v) : null);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadLists();
  }

  Future<void> _loadLists() async {
    final db = AppScope.of(context).db;
    final recent = await db.recentFoods();
    final recipes = (await db.recipes()).map((r) => r.asFood()).toList();
    final saved = widget.pick ? <SavedMeal>[] : await db.savedMeals();
    if (mounted) {
      setState(() {
        _recent = recent;
        _recipes = recipes;
        _saved = saved;
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onQuery(String q) {
    setState(() {});
    _debounce?.cancel();
    if (q.trim().length < 3 || !(_filter == _Filter.all || _filter == _Filter.packaged)) return;
    _debounce = Timer(const Duration(milliseconds: 600), () => _searchPackaged(q.trim()));
  }

  Future<void> _searchPackaged(String q) async {
    if (_packagedFor == q) return;
    setState(() {
      _packagedFor = q;
      _packagedBusy = true;
      _packagedError = null;
    });
    try {
      final r = await _off.search(q);
      if (mounted && _packagedFor == q) setState(() => _packaged = r);
    } catch (e) {
      if (mounted && _packagedFor == q) setState(() => _packagedError = e is PackagedSearchUnavailable ? e.toString() : 'Packaged food search is unavailable right now');
    } finally {
      if (mounted && _packagedFor == q) setState(() => _packagedBusy = false);
    }
  }

  Future<void> _open(Food stored) async {
    // A recent USDA food comes back from the database without its portions: restore them.
    final usda = stored.source == FoodSource.usda && stored.portions.isEmpty ? _fndds?.byName[stored.name]?.toFood() : null;
    final food = usda ?? stored;
    final result = await Navigator.push<RecipeItem>(
      context,
      MaterialPageRoute(builder: (_) => FoodDetailScreen(food: food, date: widget.date, meal: widget.meal ?? Meal.lunch, pick: widget.pick)),
    );
    if (!mounted) return;
    if (widget.pick && result != null) {
      Navigator.pop(context, result);
    } else if (result != null) {
      Navigator.pop(context);
    }
  }

  Future<void> _logSaved(SavedMeal m) async {
    final app = AppScope.of(context);
    final meal = widget.meal ?? Meal.lunch;
    await app.db.logSavedMeal(corosDate(widget.date!), meal, m);
    app.foodChanged();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Logged "${m.name}" to ${meal.label.toLowerCase()}')));
    Navigator.pop(context);
  }

  Future<void> _newRecipe([int? id]) async {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => RecipeScreen(recipeId: id)));
    await _loadLists();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.text.trim();
    final searching = q.isNotEmpty;
    bool show(_Filter f) => _filter == _Filter.all || _filter == f;
    final ifctHits = searching && show(_Filter.ifct) ? (_ifct?.search(q) ?? const []) : const <IfctFood>[];
    final usdaHits = searching && show(_Filter.usda) ? (_fndds?.search(q, limit: _filter == _Filter.usda ? 30 : 8) ?? const []) : const <FnddsFood>[];
    final recipeHits = show(_Filter.recipes) ? _recipes.where((r) => !searching || r.name.toLowerCase().contains(q.toLowerCase())).toList() : <Food>[];

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            Row(children: [
              const BackSquare(),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _query,
                  autofocus: true,
                  onChanged: _onQuery,
                  style: Tc.body,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: widget.pick ? 'Search ingredients' : 'Search foods',
                    hintStyle: Tc.label,
                    prefixIcon: const Icon(Icons.search_rounded, color: Tc.textSecondary),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final (f, label) in [
                  (_Filter.all, 'All'),
                  (_Filter.usda, 'Cooked & common'),
                  (_Filter.ifct, 'IFCT'),
                  (_Filter.packaged, 'Packaged'),
                  (_Filter.recipes, 'My recipes'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _filter == f,
                      onSelected: (_) {
                        setState(() => _filter = f);
                        _onQuery(_query.text);
                      },
                      selectedColor: Tc.goButton,
                      backgroundColor: Tc.surfaceRaised,
                      labelStyle: TextStyle(fontFamily: Tc.font, color: _filter == f ? Colors.black : Tc.text),
                      showCheckmark: false,
                      side: const BorderSide(color: Tc.hairline),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                    ),
                  ),
              ]),
            ),
            if (!searching) ...[
              if (!widget.pick && _saved.isNotEmpty && _filter == _Filter.all) ...[
                _heading('SAVED MEALS'),
                for (final m in _saved)
                  _FoodRow(
                    title: m.name,
                    subtitle: '${thousands(m.total.kcal)} kcal · ${m.items.length} items',
                    onTap: () => _logSaved(m),
                    onLongPress: () => _deleteSaved(m),
                  ),
              ],
              if (show(_Filter.recipes)) ...[
                Row(children: [
                  Expanded(child: _heading('MY RECIPES')),
                  TextButton.icon(
                    onPressed: () => _newRecipe(),
                    icon: const Icon(Icons.add_rounded, color: Tc.go, size: 18),
                    label: const Text('New recipe', style: TextStyle(color: Tc.go)),
                  ),
                ]),
                if (_recipes.isEmpty)
                  Text('Build a dish once from IFCT ingredients in grams, then log it by the serving.', style: Tc.label.copyWith(fontSize: 13)),
                for (final r in recipeHits) _recipeRow(r),
              ],
              if (_filter == _Filter.all && _recent.isNotEmpty) ...[
                _heading('RECENT'),
                for (final f in _recent.where((f) => !f.isRecipe)) f.source == FoodSource.usda && f.servingGrams != null ? _usdaRow(f) : _foodRow(f),
              ],
              if (!widget.pick && _filter == _Filter.all) ...[
                _heading('NOT IN THE LISTS?'),
                _FoodRow(title: 'Enter it manually', subtitle: 'Name, calories and macros, for this one meal', icon: Icons.edit_outlined, onTap: _manual),
              ],
            ] else ...[
              if (recipeHits.isNotEmpty) ...[_heading('MY RECIPES'), for (final r in recipeHits) _recipeRow(r)],
              if (show(_Filter.usda)) ...[
                _heading('COOKED & COMMON · USDA ESTIMATES'),
                if (usdaHits.isEmpty) Text(_fndds == null ? 'Loading…' : 'No match in USDA foods.', style: Tc.label.copyWith(fontSize: 13)),
                for (final f in usdaHits) _usdaRow(f.toFood()),
              ],
              if (show(_Filter.ifct)) ...[
                _heading('IFCT 2017 · RAW, PER 100 G'),
                if (ifctHits.isEmpty) Text(_ifct == null ? 'Loading…' : 'No IFCT match. IFCT lists raw ingredients, not dishes.', style: Tc.label.copyWith(fontSize: 13)),
                for (final f in ifctHits) _foodRow(f.food),
              ],
              if (show(_Filter.packaged)) ...[
                _heading('PACKAGED · OPEN FOOD FACTS'),
                if (q.length < 3)
                  Text('Type at least 3 letters to search packaged foods online.', style: Tc.label.copyWith(fontSize: 13))
                else if (_packagedBusy)
                  const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(color: Tc.go, strokeWidth: 2)))
                else if (_packagedError != null)
                  Text('$_packagedError. IFCT and your recipes still work offline.', style: Tc.label.copyWith(fontSize: 13))
                else if (_packaged != null && _packagedFor == q && _packaged!.isEmpty)
                  Text('No packaged match with full nutrition.', style: Tc.label.copyWith(fontSize: 13))
                else if (_packaged != null && _packagedFor == q)
                  for (final f in _packaged!) _foodRow(f),
              ],
              if (!widget.pick) ...[
                const SizedBox(height: 8),
                _FoodRow(title: 'Enter "$q" manually', subtitle: 'Name, calories and macros, for this one meal', icon: Icons.edit_outlined, onTap: _manual),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _heading(String t) => Padding(padding: const EdgeInsets.fromLTRB(4, 22, 4, 10), child: Text(t, style: Tc.caps));

  Widget _foodRow(Food f) => _FoodRow(
        title: f.name,
        subtitle: '${thousands(f.per100g.kcal)} kcal / 100 g · ${f.detail ?? f.sourceLabel}',
        chips: f.per100g,
        onTap: () => _open(f),
      );

  /// A USDA food shows its whole-item portion: "Guava, raw · 37 kcal a fruit (55 g)".
  Widget _usdaRow(Food f) => _FoodRow(
        title: f.name,
        subtitle: '${thousands(f.forGrams(f.servingGrams!).kcal)} kcal · ${f.servingName} (${f.servingGrams!.round()} g)',
        chips: f.forGrams(f.servingGrams!),
        onTap: () => _open(f),
      );

  Widget _recipeRow(Food r) => _FoodRow(
        title: r.name,
        subtitle: '${thousands(r.forGrams(r.servingGrams ?? 100).kcal)} kcal a serving · ${r.detail}',
        chips: r.forGrams(r.servingGrams ?? 100),
        onTap: () => _open(r),
        onLongPress: () => _newRecipe(r.id),
        trailingIcon: Icons.edit_outlined,
        onTrailing: () => _newRecipe(r.id),
      );

  Future<void> _deleteSaved(SavedMeal m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Tc.surface,
        title: Text('Delete "${m.name}"?', style: Tc.title(20)),
        content: Text('Meals already logged stay as they are.', style: Tc.label),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Tc.textSecondary))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Tc.coral))),
        ],
      ),
    );
    if (ok == true && mounted) {
      await AppScope.of(context).db.deleteSavedMeal(m.id!);
      await _loadLists();
    }
  }

  Future<void> _manual() async {
    final app = AppScope.of(context);
    final logged = await showManualEntry(context, widget.date!, widget.meal ?? Meal.lunch, initialName: _query.text.trim());
    if (logged == true) {
      app.foodChanged();
      if (mounted) Navigator.pop(context);
    }
  }
}

class _FoodRow extends StatelessWidget {
  const _FoodRow({required this.title, required this.subtitle, required this.onTap, this.chips, this.icon, this.onLongPress, this.trailingIcon, this.onTrailing});
  final String title;
  final String subtitle;
  final Nutrients? chips;
  final IconData? icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final IconData? trailingIcon;
  final VoidCallback? onTrailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Tc.surface,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            onLongPress: onLongPress,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: Tc.hairline)),
              child: Row(children: [
                if (icon != null) ...[Icon(icon, color: Tc.textSecondary, size: 20), const SizedBox(width: 12)],
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: Tc.body.copyWith(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Text(subtitle, style: Tc.label.copyWith(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (chips != null) ...[const SizedBox(height: 4), MacroChips(chips!, size: 12)],
                  ]),
                ),
                if (trailingIcon != null)
                  IconButton(onPressed: onTrailing, icon: Icon(trailingIcon, color: Tc.textSecondary, size: 18), tooltip: 'Edit')
                else
                  const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.add_rounded, color: Tc.go, size: 22)),
              ]),
            ),
          ),
        ),
      );
}

/// Food detail (reference ref_5, without photo, health score or vitamins): pick the amount
/// and the meal, then add.
class FoodDetailScreen extends StatefulWidget {
  const FoodDetailScreen({super.key, required this.food, this.date, required this.meal, this.pick = false});
  final Food food;
  final DateTime? date;
  final Meal meal;
  final bool pick;

  @override
  State<FoodDetailScreen> createState() => _FoodDetailScreenState();
}

class _FoodDetailScreenState extends State<FoodDetailScreen> {
  late Meal _meal = widget.meal;
  late bool _byServing = widget.food.servingGrams != null && !widget.pick;
  late double _servings = 1;
  late final _grams = TextEditingController(text: (widget.food.servingGrams ?? 100).round().toString());

  /// The household measure picked for a USDA food; otherwise the food's own serving.
  late (String, double)? _portion = widget.food.portions.isEmpty ? null : (widget.food.servingName!, widget.food.servingGrams!);
  double? get _servingGrams => _portion?.$2 ?? widget.food.servingGrams;

  double get _amount => _byServing ? _servings * _servingGrams! : (double.tryParse(_grams.text.trim()) ?? 0);

  Future<void> _add() async {
    final grams = _amount;
    if (grams <= 0) return;
    if (widget.pick) {
      Navigator.pop(context, RecipeItem(food: widget.food, grams: grams));
      return;
    }
    final app = AppScope.of(context);
    await app.db.logFood(corosDate(widget.date!), _meal, widget.food, grams, servingGrams: _byServing ? _servingGrams : null);
    app.foodChanged();
    if (mounted) Navigator.pop(context, RecipeItem(food: widget.food, grams: grams));
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.food;
    final n = f.forGrams(_amount);
    final serving = _servingGrams;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            const Align(alignment: Alignment.centerLeft, child: BackSquare()),
            const SizedBox(height: 18),
            Text(f.name, style: Tc.title(26)),
            const SizedBox(height: 6),
            Text(
              [
                f.sourceLabel,
                if (f.detail != null) f.detail!,
                if (f.isRecipe) '1 serving = ${serving!.round()} g of raw ingredients' else if (serving != null && f.portions.isEmpty) '1 serving = ${serving.round()} g',
              ].join(' · '),
              style: Tc.label.copyWith(fontSize: 14),
            ),
            const SizedBox(height: 20),
            TcCard(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Column(children: [
                if (serving != null && !f.isRecipe)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Segmented<bool>(values: const [true, false], labels: const ['Servings', 'Grams'], selected: _byServing, onChanged: (v) => setState(() => _byServing = v)),
                  ),
                Row(children: [
                  Expanded(child: Text(_byServing ? 'Servings' : 'Amount', style: Tc.label)),
                  if (_byServing)
                    AmountStepper(
                      label: _servings == _servings.roundToDouble() ? _servings.round().toString() : _servings.toStringAsFixed(1),
                      onMinus: () => setState(() => _servings = (_servings - 0.5).clamp(0.5, 50)),
                      onPlus: () => setState(() => _servings = (_servings + 0.5).clamp(0.5, 50)),
                    )
                  else
                    SizedBox(
                      width: 120,
                      child: TextField(
                        controller: _grams,
                        onChanged: (_) => setState(() {}),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textAlign: TextAlign.end,
                        style: Tc.title(20),
                        decoration: const InputDecoration(suffixText: 'g', isDense: true),
                      ),
                    ),
                ]),
                if (_byServing && f.portions.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final p in f.portions)
                        ChoiceChip(
                          label: Text('${p.$1} · ${p.$2.round()} g'),
                          selected: _portion == p,
                          onSelected: (_) => setState(() => _portion = p),
                          selectedColor: Tc.goButton,
                          backgroundColor: Tc.surfaceRaised,
                          labelStyle: TextStyle(fontFamily: Tc.font, fontSize: 12, color: _portion == p ? Colors.black : Tc.text),
                          showCheckmark: false,
                          side: const BorderSide(color: Tc.hairline),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                        ),
                    ]),
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 12),
            TcCard(
              child: Row(children: [
                Column(children: [
                  Text(thousands(n.kcal), style: Tc.title(34)),
                  Text('kcal', style: Tc.label.copyWith(fontSize: 13)),
                ]),
                const SizedBox(width: 18),
                Container(width: 1, height: 120, color: Tc.hairline),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(children: [
                    _bar('Protein', n.protein, MacroColors.protein, n),
                    _bar('Carbs', n.carbs, MacroColors.carbs, n),
                    _bar('Fat', n.fat, MacroColors.fat, n),
                    _bar('Fibre', n.fibre, MacroColors.fibre, n),
                  ]),
                ),
              ]),
            ),
            if (!widget.pick) ...[
              const SizedBox(height: 20),
              Text('MEAL', style: Tc.caps),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final m in Meal.values)
                  ChoiceChip(
                    label: Text(m.label),
                    selected: _meal == m,
                    onSelected: (_) => setState(() => _meal = m),
                    selectedColor: Tc.goButton,
                    backgroundColor: Tc.surfaceRaised,
                    labelStyle: TextStyle(fontFamily: Tc.font, color: _meal == m ? Colors.black : Tc.text),
                    showCheckmark: false,
                    side: const BorderSide(color: Tc.hairline),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                  ),
              ]),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: PillButton(
                label: widget.pick ? 'Add ingredient' : 'Add to ${_meal.label.toLowerCase()}',
                icon: Icons.add_rounded,
                onPressed: _amount > 0 ? _add : null,
              ),
            ),
            if (f.source == FoodSource.ifct) ...[
              const SizedBox(height: 16),
              Text('Values per 100 g edible portion, raw, from the Indian Food Composition Tables 2017 (National Institute of Nutrition).',
                  style: Tc.label.copyWith(fontSize: 12, height: 1.4)),
            ],
            if (f.source == FoodSource.usda) ...[
              const SizedBox(height: 16),
              Text('Estimate from USDA survey foods (FNDDS): US recipes and portions, so treat it as a rough guide.',
                  style: Tc.label.copyWith(fontSize: 12, height: 1.4)),
            ],
            if (f.source == FoodSource.packaged) ...[
              const SizedBox(height: 16),
              Text('Values from Open Food Facts, entered by its contributors. Check the label if they look off.',
                  style: Tc.label.copyWith(fontSize: 12, height: 1.4)),
            ],
          ],
        ),
      ),
    );
  }

  /// Bars show each macro's share of the food's calories (fibre against 10 g), so a glance
  /// says whether it's mostly protein, carbs or fat.
  Widget _bar(String label, double g, Color color, Nutrients n) {
    final energy = n.protein * 4 + n.carbs * 4 + n.fat * 9;
    final share = label == 'Fibre'
        ? (g / 10).clamp(0.0, 1.0)
        : energy == 0
            ? 0.0
            : ((label == 'Fat' ? g * 9 : g * 4) / energy).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label, style: Tc.body.copyWith(fontSize: 14, fontWeight: FontWeight.w500))),
          Text('${grams(g)} g', style: Tc.label.copyWith(fontSize: 14)),
        ]),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: share, minHeight: 4, color: color, backgroundColor: Tc.muted),
        ),
      ]),
    );
  }
}
