import 'package:sqflite/sqflite.dart';

import '../food/food.dart';
import 'app_database.dart';

/// Reads and writes for the food and body log (M4). Tables are created in app_database.dart.
extension FoodStore on AppDatabase {
  static Map<String, Object?> _foodRow(Food f) => {
        'source': f.source.name,
        'source_id': f.sourceId,
        'name': f.name,
        'detail': f.detail,
        'kcal': f.per100g.kcal,
        'protein': f.per100g.protein,
        'carbs': f.per100g.carbs,
        'fat': f.per100g.fat,
        'fibre': f.per100g.fibre,
        'serving_g': f.servingGrams,
        'serving_name': f.servingName,
      };

  static Food _food(Map<String, Object?> r) => Food(
        id: r['id'] as int,
        source: FoodSource.values.byName(r['source'] as String),
        sourceId: r['source_id'] as String?,
        name: r['name'] as String,
        detail: r['detail'] as String?,
        per100g: Nutrients(
          kcal: (r['kcal'] as num).toDouble(),
          protein: (r['protein'] as num).toDouble(),
          carbs: (r['carbs'] as num).toDouble(),
          fat: (r['fat'] as num).toDouble(),
          fibre: (r['fibre'] as num).toDouble(),
        ),
        servingGrams: (r['serving_g'] as num?)?.toDouble(),
        servingName: r['serving_name'] as String?,
      );

  /// Stores an IFCT or packaged food the first time it's used (matched on its code), so it
  /// shows under recents and can go into recipes and saved meals. Returns it with its id.
  Future<Food> rememberFood(Food f) async {
    if (f.id != null) return f;
    if (f.sourceId != null) {
      final existing = await db.query('foods', where: 'source = ? AND source_id = ?', whereArgs: [f.source.name, f.sourceId]);
      if (existing.isNotEmpty) {
        final id = existing.first['id'] as int;
        await db.update('foods', {..._foodRow(f), 'archived': 0}, where: 'id = ?', whereArgs: [id]);
        return f.withId(id);
      }
    }
    return f.withId(await db.insert('foods', _foodRow(f)));
  }

  Future<Food?> foodById(int id) async {
    final rows = await db.query('foods', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _food(rows.first);
  }

  /// Foods and recipes logged most recently, newest first.
  Future<List<Food>> recentFoods({int limit = 20}) async =>
      (await db.query('foods', where: "last_used_at IS NOT NULL AND archived = 0 AND source != 'manual'", orderBy: 'last_used_at DESC', limit: limit))
          .map(_food)
          .toList();

  // ---- recipes

  Future<int> saveRecipe(Recipe r) async {
    final items = <RecipeItem>[for (final i in r.items) RecipeItem(food: await rememberFood(i.food), grams: i.grams)];
    final saved = Recipe(id: r.id, name: r.name, items: items, servings: r.servings);
    return db.transaction((txn) async {
      final row = {..._foodRow(saved.asFood()), 'servings': saved.servings};
      final id = r.id ?? await txn.insert('foods', row);
      if (r.id != null) await txn.update('foods', row, where: 'id = ?', whereArgs: [id]);
      await txn.delete('recipe_items', where: 'recipe_id = ?', whereArgs: [id]);
      for (var i = 0; i < items.length; i++) {
        await txn.insert('recipe_items', {'recipe_id': id, 'position': i, 'food_id': items[i].food.id, 'grams': items[i].grams});
      }
      return id;
    });
  }

  Future<List<Recipe>> recipes() async {
    final rows = await db.query('foods', where: "source = 'recipe' AND archived = 0", orderBy: 'name COLLATE NOCASE');
    return [for (final r in rows) await _recipe(r)];
  }

  Future<Recipe?> recipeById(int id) async {
    final rows = await db.query('foods', where: "id = ? AND source = 'recipe'", whereArgs: [id]);
    return rows.isEmpty ? null : _recipe(rows.first);
  }

  Future<Recipe> _recipe(Map<String, Object?> r) async {
    final items = await db.rawQuery(
        'SELECT f.*, i.grams AS item_grams FROM recipe_items i JOIN foods f ON f.id = i.food_id WHERE i.recipe_id = ? ORDER BY i.position', [r['id']]);
    return Recipe(
      id: r['id'] as int,
      name: r['name'] as String,
      servings: (r['servings'] as int?) ?? 1,
      items: [for (final i in items) RecipeItem(food: _food(i), grams: (i['item_grams'] as num).toDouble())],
    );
  }

  /// Brings stored IFCT foods in line with the bundled table (it was corrected on 5 Oct 2026:
  /// oils and ghee had 0 kcal), then recalculates recipes that use a changed food. Meals
  /// already logged keep the values they were logged with. Returns the recipes recalculated.
  Future<List<String>> refreshIfctFoods(Map<String, Food> byCode) async {
    final changed = <int>{};
    for (final r in await db.query('foods', where: "source = 'ifct'")) {
      final fresh = byCode[r['source_id']];
      if (fresh == null) continue;
      final old = _food(r).per100g;
      final n = fresh.per100g;
      if ((old.kcal - n.kcal).abs() > 0.5 || (old.protein - n.protein).abs() > 0.01 || (old.carbs - n.carbs).abs() > 0.01 || (old.fat - n.fat).abs() > 0.01) {
        await db.update('foods', {'kcal': n.kcal, 'protein': n.protein, 'carbs': n.carbs, 'fat': n.fat, 'fibre': n.fibre}, where: 'id = ?', whereArgs: [r['id']]);
        changed.add(r['id'] as int);
      }
    }
    if (changed.isEmpty) return [];
    final ids = changed.join(',');
    final recipeIds = (await db.rawQuery('SELECT DISTINCT recipe_id FROM recipe_items WHERE food_id IN ($ids)')).map((r) => r['recipe_id'] as int);
    final names = <String>[];
    for (final id in recipeIds) {
      final recipe = await recipeById(id);
      if (recipe == null) continue;
      await saveRecipe(recipe);
      names.add(recipe.name);
    }
    return names;
  }

  /// Hides a recipe from search; meals already logged with it keep their values.
  Future<void> archiveFood(int id) => db.update('foods', {'archived': 1}, where: 'id = ?', whereArgs: [id]);

  // ---- meal entries

  /// [servingGrams] overrides the food's own serving, for a USDA portion picked on screen.
  Future<int> logFood(String date, Meal meal, Food food, double grams, {double? servingGrams}) async {
    final f = await rememberFood(food);
    await db.update('foods', {'last_used_at': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [f.id]);
    return addEntry(MealEntry(date: date, meal: meal, foodId: f.id, name: f.name, grams: grams, nutrients: f.forGrams(grams), servingGrams: servingGrams ?? f.servingGrams));
  }

  Future<int> addEntry(MealEntry e) => db.insert('meal_entries', {
        'date': e.date,
        'meal': e.meal.name,
        'food_id': e.foodId,
        'name': e.name,
        'grams': e.grams,
        'kcal': e.nutrients.kcal,
        'protein': e.nutrients.protein,
        'carbs': e.nutrients.carbs,
        'fat': e.nutrients.fat,
        'fibre': e.nutrients.fibre,
        'serving_g': e.servingGrams,
        'created_at': DateTime.now().toIso8601String(),
      });

  /// Changes the amount, scaling the stored nutrients (the serving steppers on the Log screen).
  Future<void> setEntryGrams(MealEntry e, double grams) async {
    if (grams <= 0) return deleteEntry(e.id!);
    final n = e.grams == 0 ? e.nutrients : e.nutrients.scale(grams / e.grams);
    await db.update('meal_entries', {'grams': grams, 'kcal': n.kcal, 'protein': n.protein, 'carbs': n.carbs, 'fat': n.fat, 'fibre': n.fibre},
        where: 'id = ?', whereArgs: [e.id]);
  }

  Future<void> deleteEntry(int id) => db.delete('meal_entries', where: 'id = ?', whereArgs: [id]);

  Future<List<MealEntry>> entriesBetween(String from, String to) async =>
      (await db.query('meal_entries', where: 'date BETWEEN ? AND ?', whereArgs: [from, to], orderBy: 'date, id')).map((r) => MealEntry(
            id: r['id'] as int,
            date: r['date'] as String,
            meal: Meal.values.byName(r['meal'] as String),
            foodId: r['food_id'] as int?,
            name: r['name'] as String,
            grams: (r['grams'] as num).toDouble(),
            servingGrams: (r['serving_g'] as num?)?.toDouble(),
            nutrients: Nutrients(
              kcal: (r['kcal'] as num).toDouble(),
              protein: (r['protein'] as num).toDouble(),
              carbs: (r['carbs'] as num).toDouble(),
              fat: (r['fat'] as num).toDouble(),
              fibre: (r['fibre'] as num).toDouble(),
            ),
          )).toList();

  Future<List<MealEntry>> entriesOn(String date) => entriesBetween(date, date);

  // ---- saved meals

  Future<int> saveSavedMeal(SavedMeal m) async {
    final items = <SavedMealItem>[for (final i in m.items) SavedMealItem(food: await rememberFood(i.food), grams: i.grams)];
    return db.transaction((txn) async {
      final id = await txn.insert('saved_meals', {'name': m.name, 'created_at': DateTime.now().toIso8601String()});
      for (var i = 0; i < items.length; i++) {
        await txn.insert('saved_meal_items', {'saved_meal_id': id, 'position': i, 'food_id': items[i].food.id, 'grams': items[i].grams});
      }
      return id;
    });
  }

  Future<List<SavedMeal>> savedMeals() async {
    final meals = await db.query('saved_meals', orderBy: 'name COLLATE NOCASE');
    return [
      for (final m in meals)
        SavedMeal(
          id: m['id'] as int,
          name: m['name'] as String,
          items: [
            for (final i in await db.rawQuery(
                'SELECT f.*, s.grams AS item_grams FROM saved_meal_items s JOIN foods f ON f.id = s.food_id WHERE s.saved_meal_id = ? ORDER BY s.position',
                [m['id']]))
              SavedMealItem(food: _food(i), grams: (i['item_grams'] as num).toDouble()),
          ],
        ),
    ];
  }

  Future<void> deleteSavedMeal(int id) => db.transaction((txn) async {
        await txn.delete('saved_meal_items', where: 'saved_meal_id = ?', whereArgs: [id]);
        await txn.delete('saved_meals', where: 'id = ?', whereArgs: [id]);
      });

  /// Logs every item of a saved meal into [meal] on [date].
  Future<void> logSavedMeal(String date, Meal meal, SavedMeal m) async {
    for (final i in m.items) {
      await logFood(date, meal, i.food, i.grams);
    }
  }

  // ---- body weight and active calories

  Future<void> saveWeight(String date, double kg) =>
      db.insert('weights', {'date': date, 'kg': kg}, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> deleteWeight(String date) => db.delete('weights', where: 'date = ?', whereArgs: [date]);

  Future<Map<String, double>> weightsBetween(String from, String to) async => {
        for (final r in await db.query('weights', where: 'date BETWEEN ? AND ?', whereArgs: [from, to], orderBy: 'date'))
          r['date'] as String: (r['kg'] as num).toDouble(),
      };

  Future<void> saveDailyHealth(Map<String, int?> activeKcal) async {
    final batch = db.batch();
    activeKcal.forEach((date, kcal) {
      if (kcal != null) batch.insert('daily_health', {'date': date, 'active_kcal': kcal}, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    await batch.commit(noResult: true);
  }

  Future<Map<String, int>> activeKcalBetween(String from, String to) async => {
        for (final r in await db.query('daily_health', where: 'date BETWEEN ? AND ? AND active_kcal IS NOT NULL', whereArgs: [from, to]))
          r['date'] as String: r['active_kcal'] as int,
      };
}
