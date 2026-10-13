/// Food and body log models (PRD F4, M4).
library;

/// usda: FNDDS survey foods, cooked dishes and fruits with household portions (5 Oct 2026).
enum FoodSource { ifct, packaged, recipe, manual, usda }

/// Meal sections on the Log screen. Run fuel covers gels and drinks around runs (owner, 5 Oct 2026).
enum Meal { breakfast, lunch, dinner, snacks, runFuel }

extension MealLabel on Meal {
  String get label => switch (this) {
        Meal.breakfast => 'Breakfast',
        Meal.lunch => 'Lunch',
        Meal.dinner => 'Dinner',
        Meal.snacks => 'Snacks',
        Meal.runFuel => 'Run fuel',
      };
}

/// Calories and macros. Used per 100 g for foods, and as totals for entries and days.
class Nutrients {
  const Nutrients({required this.kcal, required this.protein, required this.carbs, required this.fat, this.fibre = 0});

  static const zero = Nutrients(kcal: 0, protein: 0, carbs: 0, fat: 0);

  final double kcal;
  final double protein;
  final double carbs;
  final double fat;
  final double fibre;

  Nutrients operator +(Nutrients o) =>
      Nutrients(kcal: kcal + o.kcal, protein: protein + o.protein, carbs: carbs + o.carbs, fat: fat + o.fat, fibre: fibre + o.fibre);

  Nutrients scale(double f) => Nutrients(kcal: kcal * f, protein: protein * f, carbs: carbs * f, fat: fat * f, fibre: fibre * f);

  static Nutrients sum(Iterable<Nutrients> all) => all.fold(zero, (a, b) => a + b);
}

/// Anything that can be logged. Values are always per 100 g, so every amount is stored in grams.
/// A recipe's 100 g is 100 g of its raw ingredients; [servingGrams] is one serving of that.
class Food {
  Food({
    this.id,
    required this.source,
    this.sourceId,
    required this.name,
    this.detail,
    required this.per100g,
    this.servingGrams,
    this.servingName,
    this.portions = const [],
  });

  final int? id;
  final FoodSource source;

  /// IFCT code, Open Food Facts barcode, or the USDA food's name.
  final String? sourceId;
  final String name;

  /// IFCT food group, or the brand for a packaged food.
  final String? detail;
  final Nutrients per100g;
  final double? servingGrams;
  final String? servingName;

  /// Household measures to pick from (USDA foods), e.g. ("1 fruit", 55). Not stored.
  final List<(String, double)> portions;

  bool get isRecipe => source == FoodSource.recipe;

  Nutrients forGrams(double grams) => per100g.scale(grams / 100);

  Food withId(int id) => Food(
      id: id, source: source, sourceId: sourceId, name: name, detail: detail, per100g: per100g, servingGrams: servingGrams, servingName: servingName, portions: portions);

  /// "IFCT", "Packaged", "Recipe" for list rows.
  String get sourceLabel => switch (source) {
        FoodSource.ifct => 'IFCT',
        FoodSource.packaged => 'Packaged',
        FoodSource.recipe => 'Recipe',
        FoodSource.manual => 'My entry',
        FoodSource.usda => 'USDA',
      };
}

/// One logged item. Nutrients are copied at logging time, so editing a recipe later
/// doesn't rewrite what was eaten.
class MealEntry {
  MealEntry({this.id, required this.date, required this.meal, this.foodId, required this.name, required this.grams, required this.nutrients, this.servingGrams});

  final int? id;
  final String date; // yyyy-MM-dd
  final Meal meal;
  final int? foodId;
  final String name;
  final double grams;
  final Nutrients nutrients;

  /// Set for foods logged by the serving, so the row can say "2 servings".
  final double? servingGrams;

  double? get servings => servingGrams == null || servingGrams == 0 ? null : grams / servingGrams!;
}

class RecipeItem {
  RecipeItem({required this.food, required this.grams});
  final Food food;
  final double grams;
}

/// A dish built from ingredients in raw grams, split into servings (owner, 5 Oct 2026).
class Recipe {
  Recipe({this.id, required this.name, required this.items, required this.servings});

  final int? id;
  final String name;
  final List<RecipeItem> items;
  final int servings;

  double get totalGrams => items.fold(0.0, (s, i) => s + i.grams);
  Nutrients get total => Nutrients.sum(items.map((i) => i.food.forGrams(i.grams)));
  Nutrients get perServing => total.scale(1 / servings);

  Food asFood() => Food(
        id: id,
        source: FoodSource.recipe,
        name: name,
        detail: '${items.length} ingredient${items.length == 1 ? '' : 's'}',
        per100g: totalGrams == 0 ? Nutrients.zero : total.scale(100 / totalGrams),
        servingGrams: totalGrams / servings,
        servingName: 'serving',
      );
}

class SavedMealItem {
  SavedMealItem({required this.food, required this.grams});
  final Food food;
  final double grams;
}

/// A meal saved from the Log screen ("my usual breakfast"), logged again in one tap.
class SavedMeal {
  SavedMeal({this.id, required this.name, required this.items});
  final int? id;
  final String name;
  final List<SavedMealItem> items;

  Nutrients get total => Nutrients.sum(items.map((i) => i.food.forGrams(i.grams)));
}

/// "52P 120C 18F" style chips use whole grams.
String grams(double g) => g < 10 && g != g.roundToDouble() ? g.toStringAsFixed(1) : g.round().toString();
