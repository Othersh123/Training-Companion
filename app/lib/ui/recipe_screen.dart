import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../data/food_store.dart';
import '../food/food.dart';
import 'food_search_screen.dart';
import 'food_widgets.dart';
import 'theme.dart';

/// Recipe builder (owner, 5 Oct 2026): a dish from raw ingredients in grams, split into
/// servings. Logged by the serving afterwards.
class RecipeScreen extends StatefulWidget {
  const RecipeScreen({super.key, this.recipeId});
  final int? recipeId;

  @override
  State<RecipeScreen> createState() => _RecipeScreenState();
}

class _RecipeScreenState extends State<RecipeScreen> {
  final _name = TextEditingController();
  final _items = <RecipeItem>[];
  int _servings = 2;
  bool _loaded = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final id = widget.recipeId;
    if (id != null) {
      AppScope.of(context).db.recipeById(id).then((r) {
        if (r == null || !mounted) return;
        setState(() {
          _name.text = r.name;
          _servings = r.servings;
          _items.addAll(r.items);
        });
      });
    }
  }

  Recipe get _recipe => Recipe(id: widget.recipeId, name: _name.text.trim(), items: _items, servings: _servings);

  Future<void> _add() async {
    final item = await pickIngredient(context);
    if (item != null) setState(() => _items.add(item));
  }

  Future<void> _editGrams(int i) async {
    final c = TextEditingController(text: _items[i].grams.round().toString());
    final g = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Tc.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text(_items[i].food.name, style: Tc.title(18)),
        content: TextField(controller: c, autofocus: true, keyboardType: TextInputType.number, style: Tc.title(22), decoration: const InputDecoration(suffixText: 'g raw')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Tc.textSecondary))),
          TextButton(onPressed: () => Navigator.pop(ctx, double.tryParse(c.text.trim())), child: const Text('Save', style: TextStyle(color: Tc.go))),
        ],
      ),
    );
    if (g != null && g > 0) setState(() => _items[i] = RecipeItem(food: _items[i].food, grams: g));
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return setState(() => _error = 'Give the dish a name.');
    if (_items.isEmpty) return setState(() => _error = 'Add at least one ingredient.');
    final app = AppScope.of(context);
    await app.db.saveRecipe(_recipe);
    app.foodChanged();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final app = AppScope.of(context);
    await app.db.archiveFood(widget.recipeId!);
    app.foodChanged();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final r = _recipe;
    final perServing = r.perServing;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            Row(children: [
              const BackSquare(),
              const SizedBox(width: 14),
              Expanded(child: Text(widget.recipeId == null ? 'New recipe' : 'Edit recipe', style: Tc.title(26))),
              if (widget.recipeId != null) TextButton(onPressed: _delete, child: const Text('Delete', style: TextStyle(color: Tc.coral))),
            ]),
            const SizedBox(height: 20),
            TextField(
              controller: _name,
              onChanged: (_) => setState(() {}),
              style: Tc.body,
              decoration: InputDecoration(labelText: 'Dish name', hintText: 'e.g. Toor dal tadka', labelStyle: Tc.label),
            ),
            const SizedBox(height: 14),
            TcCard(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Makes', style: Tc.body),
                    Text('servings in the whole pot', style: Tc.label.copyWith(fontSize: 13)),
                  ]),
                ),
                AmountStepper(
                  label: '$_servings',
                  onMinus: () => setState(() => _servings = (_servings - 1).clamp(1, 50)),
                  onPlus: () => setState(() => _servings = (_servings + 1).clamp(1, 50)),
                ),
              ]),
            ),
            Padding(padding: const EdgeInsets.fromLTRB(4, 22, 4, 10), child: Text('INGREDIENTS, RAW WEIGHT', style: Tc.caps)),
            for (final (i, item) in _items.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: Tc.surface,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _editGrams(i),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: Tc.hairline)),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(item.food.name, style: Tc.body.copyWith(fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
                            Text('${item.grams.round()} g · ${thousands(item.food.forGrams(item.grams).kcal)} kcal', style: Tc.label.copyWith(fontSize: 13)),
                          ]),
                        ),
                        IconButton(
                          tooltip: 'Remove',
                          onPressed: () => setState(() => _items.removeAt(i)),
                          icon: const Icon(Icons.close_rounded, color: Tc.textSecondary, size: 18),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            InkWell(
              borderRadius: BorderRadius.circular(28),
              onTap: _add,
              child: const EmptyCard(title: 'Add an ingredient', subtitle: 'Search IFCT or packaged foods, then enter grams'),
            ),
            const SizedBox(height: 16),
            TcCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('PER SERVING', style: Tc.caps),
                const SizedBox(height: 8),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(thousands(perServing.kcal), style: Tc.title(30)),
                  const SizedBox(width: 6),
                  Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('kcal', style: Tc.label)),
                ]),
                const SizedBox(height: 6),
                MacroChips(perServing, size: 14),
                const SizedBox(height: 8),
                Text('Cooking adds or loses water, not calories: weigh ingredients raw and split the pot into servings.',
                    style: Tc.label.copyWith(fontSize: 12, height: 1.4)),
              ]),
            ),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: Tc.label.copyWith(color: Tc.coral))),
            const SizedBox(height: 20),
            SizedBox(width: double.infinity, child: PillButton(label: 'Save recipe', onPressed: _save)),
          ],
        ),
      ),
    );
  }
}
