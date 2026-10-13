import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:training_companion/coros/parsers.dart';
import 'package:training_companion/data/app_database.dart';
import 'package:training_companion/data/food_store.dart';
import 'package:training_companion/data/goal.dart';
import 'package:training_companion/food/fndds.dart';
import 'package:training_companion/food/food.dart';
import 'package:training_companion/food/ifct.dart';
import 'package:training_companion/food/open_food_facts.dart';
import 'package:training_companion/food/targets.dart';
import 'package:training_companion/rules/planned_workout.dart';
import 'package:training_companion/sync/coros_sync.dart';
import 'package:training_companion/sync/food_day.dart';

import 'coros_sync_test.dart' show FixtureCoros;

String fixture(String path) => File('test/fixtures/$path').readAsStringSync();

class _NoCoros implements ToolCaller {
  @override
  Future<String> callTool(String name, Map<String, dynamic> args) => throw UnimplementedError();
}

void main() {
  final ifct = Ifct.fromJson(File('assets/food/ifct2017.json').readAsStringSync());
  Food ifctFood(String code) => ifct.foods.firstWhere((f) => f.food.sourceId == code).food;

  group('IFCT 2017', () {
    test('all 542 foods load, per 100 g', () {
      expect(ifct.foods, hasLength(542));
      final dal = ifct.foods.firstWhere((f) => f.food.name == 'Red gram, dal').food;
      expect(dal.per100g.kcal, 331);
      expect(dal.per100g.protein, closeTo(21.7, 0.01));
    });

    test('regional names are searchable: "toor" finds Red gram', () {
      expect(ifct.search('toor').map((f) => f.food.name), contains('Red gram, dal'));
    });

    test('every word must match, and names starting with the query come first', () {
      final rice = ifct.search('rice raw');
      expect(rice, isNotEmpty);
      expect(rice.every((f) => f.food.name.toLowerCase().contains('rice') || f.local.toLowerCase().contains('rice')), isTrue);
      expect(rice.first.food.name.toLowerCase(), startsWith('rice'));
      expect(ifct.search('   '), isEmpty);
    });
  });

  group('USDA estimates for manual entries (owner, 5 Oct 2026)', () {
    final fndds = Fndds.fromJson(File('assets/food/fndds.json').readAsStringSync());

    test('everyday names find the plain food first, with a whole-item portion', () {
      final guava = fndds.search('guava').first;
      expect(guava.name, 'Guava, raw');
      expect(guava.defaultPortion, ('1 fruit', 55.0));
      expect(fndds.search('chapati').first.name, 'Bread, chappatti or roti');
      expect(fndds.search('roti').first.name, 'Bread, chappatti or roti'); // not rotisserie chicken
      expect(fndds.search('roti').first.defaultPortion.$1, contains('medium'));
      expect(fndds.search('rice').first.name, startsWith('Rice, '));
      expect(fndds.search('egg').first.defaultPortion, ('1 egg', 50.0));
    });

    test('USDA spellings: tofu is "Soybean curd", sourdough is French bread (owner\'s entries, 5 Oct 2026)', () {
      expect(fndds.search('tofu').first.name, 'Soybean curd');
      expect(fndds.search('sourdough bread').first.name, 'Bread, French or Vienna');
      expect(fndds.search('cooked rice').first.name, 'Rice, cooked, NFS');
    });

    test('no exact match falls back to the last word', () {
      expect(fndds.search('multigrain loaf bread').first.name, startsWith('Bread'));
    });

    test('a combined entry splits into its parts', () {
      expect(Fndds.parts('Rice + Chapati'), ['Rice', 'Chapati']);
      expect(Fndds.parts('Sourdough Bread + Egg'), ['Sourdough Bread', 'Egg']);
      expect(Fndds.parts('dosa with chutney and sambar'), ['dosa', 'chutney', 'sambar']);
      expect(Fndds.parts('guava'), ['guava']);
    });

    test('typed macros that don\'t add up to the calories are caught', () {
      expect(macrosDisagree(600, 15, 600, 15), isTrue); // the owner's "Rice + Chapati": about 2,600 kcal
      expect(macrosDisagree(100, 2, 100, 0), isTrue); // "Guava": about 410 kcal
      expect(macrosDisagree(350, 12, 45, 13), isFalse);
      expect(macrosDisagree(40, 0, 0, 0), isFalse); // small gaps are fine
    });
  });

  group('Open Food Facts', () {
    final foods = parseOffSearch(fixture('food/off_search_paneer.json'));

    test('keeps products with protein, carbs and fat; joins brands', () {
      expect(foods.first.name, 'Malai Paneer');
      expect(foods.first.detail, 'Amul');
      expect(foods.first.per100g.kcal, 314);
      expect(foods.first.source, FoodSource.packaged);
      expect(foods.first.sourceId, '8901262180016');
    });

    test('missing calories are worked out from the macros', () {
      final noKcal = foods.firstWhere((f) => f.sourceId == '3383388338338338');
      expect(noKcal.per100g.kcal, closeTo(17 * 4 + 2.5 * 4 + 20 * 9, 0.01));
    });

    test('a reply without hits is a format error', () {
      expect(() => parseOffSearch('{"error":"x"}'), throwsFormatException);
    });
  });

  group('queryDailyHealthData (active calories)', () {
    test('reads Calories per day, including today so far', () {
      expect(parseDailyHealth(fixture('coros/daily_health_3d.txt')), {'2026-10-03': 463, '2026-10-04': 987, '2026-10-05': 540});
    });

    test('thousands separators', () {
      expect(parseDailyHealth(fixture('coros/daily_health_7d.txt'))['2026-09-27'], 2976);
    });

    test('a changed header is a format error', () {
      expect(() => parseDailyHealth('Health Summary\n--- 20261005 ---'), throwsA(isA<CorosFormatException>()));
    });
  });

  group('day type', () {
    PlannedWorkout planned(String name, {bool hard = false, bool long = false}) =>
        PlannedWorkout(date: '2026-10-06', name: name, sport: WorkoutSport.run, hard: hard, long: long, estimatedMeters: 8000);
    Activity done(int minutes) => Activity(
        labelId: 'x', sportType: 100, name: 'Run', date: '2026-10-06', start: DateTime(2026, 10, 6, 6), end: DateTime(2026, 10, 6, 7),
        durationSeconds: minutes * 60);

    test('the plan decides; the heavier of plan and Coros wins', () {
      expect(dayTypeFor(planned: [planned('Threshold Workout', hard: true)], done: []).type, DayType.hard);
      expect(dayTypeFor(planned: [planned('7k Easy')], done: []).type, DayType.easy);
      expect(dayTypeFor(planned: [planned('7k Easy')], done: [done(95)]).type, DayType.hard);
      expect(dayTypeFor(planned: [], done: [done(45)]).type, DayType.easy);
      expect(dayTypeFor(planned: [], done: [done(10)]).type, DayType.rest);
      expect(dayTypeFor(planned: [], done: []).reason, 'Nothing planned or done');
    });
  });

  group('targets (owner: 78.6 kg, 175 cm, 31, male)', () {
    final owner = Body(weightKg: 78.6, heightCm: 175, age: 31, male: true);
    DayTypeResult type(DayType t) => DayTypeResult(t, 'test');

    test('resting energy is about 1,730 kcal, as in the PRD', () {
      expect(owner.restingKcal, closeTo(1729.75, 0.01));
    });

    test('a rest day: 3 g/kg carbs, 1.6 g/kg protein, fat takes the rest', () {
      final t = computeFoodTargets(day: DateTime(2026, 10, 5), body: owner, dayType: type(DayType.rest), activeKcal: 400);
      expect(t.carbs, closeTo(235.8, 0.1));
      expect(t.protein, closeTo(125.8, 0.1));
      expect(t.kcal, closeTo(2129.75, 0.01));
      expect(t.fat, closeTo((2129.75 - 4 * 125.76 - 4 * 235.8) / 9, 0.01));
      expect(t.deficitNote, isNull);
      expect(t.fibre, closeTo(2129.75 * 14 / 1000, 0.01)); // about 30 g
    });

    test('a hard day: 7 g/kg carbs, and calories rise so fat stays at 20%', () {
      final t = computeFoodTargets(day: DateTime(2026, 10, 11), body: owner, dayType: type(DayType.hard), activeKcal: 1200);
      expect(t.carbs, closeTo(550.2, 0.1));
      expect(t.fat * 9 / t.kcal, closeTo(0.20, 0.001));
    });

    final goal = WeightPlan(targetKg: 72, by: DateTime(2026, 12, 31));

    test('weight goal: up to 500 kcal off a rest day, less if fat would drop under 20%', () {
      final t = computeFoodTargets(day: DateTime(2026, 10, 5), body: owner, dayType: type(DayType.rest), activeKcal: 400, weightGoal: goal);
      expect(t.deficit, greaterThan(0));
      expect(t.deficit, lessThanOrEqualTo(500));
      expect(t.fat * 9 / t.kcal, greaterThanOrEqualTo(0.199));
      expect(t.deficitNote, contains('kcal deficit'));
    });

    test('calories win on easy deficit days: carbs drop to fit, not below 3 g/kg (owner, 5 Oct 2026)', () {
      final easy = computeFoodTargets(day: DateTime(2026, 10, 6), body: owner, dayType: type(DayType.easy), activeKcal: 463, weightGoal: goal);
      expect(easy.carbs / 78.6, closeTo(3.0, 0.001)); // 5 g/kg would leave no deficit at all
      expect(easy.deficit, closeTo(385, 1));
      expect(easy.kcal, closeTo(1807.8, 0.5));
      expect(easy.fat * 9 / easy.kcal, closeTo(0.20, 0.001));
      // Without a weight goal an easy day keeps its 5 g/kg.
      final noGoal = computeFoodTargets(day: DateTime(2026, 10, 6), body: owner, dayType: type(DayType.easy), activeKcal: 463);
      expect(noGoal.carbs / 78.6, closeTo(5.0, 0.001));
    });

    test('no deficit on hard days, or from 2 weeks before a race to 1 week after (owner, 5 Oct 2026)', () {
      final hard = computeFoodTargets(day: DateTime(2026, 10, 11), body: owner, dayType: type(DayType.hard), activeKcal: 1200, weightGoal: goal);
      expect(hard.deficit, 0);
      expect(hard.deficitNote, contains('hard or long days'));
      final race = DateTime(2026, 11, 27);
      for (final d in [DateTime(2026, 11, 13), DateTime(2026, 11, 27), DateTime(2026, 12, 4)]) {
        final t = computeFoodTargets(day: d, body: owner, dayType: type(DayType.rest), activeKcal: 300, weightGoal: goal, races: [race]);
        expect(t.deficit, 0, reason: '$d');
        expect(t.deficitNote, contains('before a race'));
      }
      final after = computeFoodTargets(day: DateTime(2026, 12, 5), body: owner, dayType: type(DayType.rest), activeKcal: 300, weightGoal: goal, races: [race]);
      expect(after.deficit, greaterThan(0));
    });

    test('7-day average weight', () {
      expect(sevenDayAverage({'2026-10-05': 78.0, '2026-10-03': 79.0, '2026-09-20': 90.0}, DateTime(2026, 10, 5)), 78.5);
      expect(sevenDayAverage({}, DateTime(2026, 10, 5)), isNull);
    });
  });

  group('food store', () {
    late AppDatabase db;
    setUpAll(sqfliteFfiInit);
    setUp(() async => db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath, ownConnection: true));
    tearDown(() => db.close());

    test('logging an IFCT food stores it once, copies its nutrients and lists it under recents', () async {
      final dal = ifctFood('B021');
      await db.logFood('2026-10-05', Meal.lunch, dal, 60);
      await db.logFood('2026-10-05', Meal.dinner, dal, 40);
      final entries = await db.entriesOn('2026-10-05');
      expect(entries, hasLength(2));
      expect(entries.first.nutrients.kcal, closeTo(dal.per100g.kcal * 0.6, 0.01));
      expect(await db.recentFoods(), hasLength(1));
    });

    test('the serving stepper scales an entry; zero removes it', () async {
      await db.logFood('2026-10-05', Meal.breakfast, ifctFood('B021'), 50);
      final e = (await db.entriesOn('2026-10-05')).single;
      await db.setEntryGrams(e, 100);
      expect((await db.entriesOn('2026-10-05')).single.nutrients.kcal, closeTo(e.nutrients.kcal * 2, 0.01));
      await db.setEntryGrams((await db.entriesOn('2026-10-05')).single, 0);
      expect(await db.entriesOn('2026-10-05'), isEmpty);
    });

    test('a recipe: raw ingredients split into servings, logged by the serving', () async {
      final dal = ifctFood('B021');
      final ghee = ifct.search('ghee').first.food;
      final id = await db.saveRecipe(Recipe(name: 'Toor dal tadka', servings: 3, items: [RecipeItem(food: dal, grams: 150), RecipeItem(food: ghee, grams: 15)]));
      final recipe = (await db.recipeById(id))!;
      expect(recipe.items, hasLength(2));
      final perServing = recipe.perServing.kcal;
      expect(perServing, closeTo((dal.per100g.kcal * 1.5 + ghee.per100g.kcal * 0.15) / 3, 0.01));

      final food = recipe.asFood().withId(id);
      await db.logFood('2026-10-05', Meal.lunch, food, food.servingGrams! * 2);
      final e = (await db.entriesOn('2026-10-05')).single;
      expect(e.servings, closeTo(2, 0.001));
      expect(e.nutrients.kcal, closeTo(perServing * 2, 0.01));

      // Editing the recipe later doesn't change what was eaten.
      await db.saveRecipe(Recipe(id: id, name: 'Toor dal tadka', servings: 3, items: [RecipeItem(food: dal, grams: 150)]));
      expect((await db.entriesOn('2026-10-05')).single.nutrients.kcal, closeTo(perServing * 2, 0.01));
    });

    test('IFCT oils had 0 kcal; the corrected table fixes stored foods and recalculates recipes (5 Oct 2026)', () async {
      expect(ifct.byCode['T001']!.per100g.kcal, 900); // coconut oil, now from its 100 g of fat
      expect(ifct.byCode['T013']!.per100g.kcal, 900); // ghee
      // The owner's phone stored coconut oil at 0 kcal inside "Horse gram saaru".
      final zeroOil = Food(source: FoodSource.ifct, sourceId: 'T001', name: 'Coconut oil', per100g: const Nutrients(kcal: 0, protein: 0, carbs: 0, fat: 100));
      final id = await db.saveRecipe(Recipe(name: 'Horse gram saaru', servings: 1, items: [
        RecipeItem(food: ifct.byCode['B012']!, grams: 50),
        RecipeItem(food: zeroOil, grams: 10),
      ]));
      final before = (await db.recipeById(id))!.perServing.kcal;
      expect(await db.refreshIfctFoods(ifct.byCode), ['Horse gram saaru']);
      final after = (await db.recipeById(id))!;
      expect(after.perServing.kcal, closeTo(before + 90, 0.5));
      expect((await db.foodById(after.id!))!.forGrams(after.asFood().servingGrams!).kcal, closeTo(after.perServing.kcal, 0.5));
      expect(await db.refreshIfctFoods(ifct.byCode), isEmpty); // nothing left to fix
    });

    test('a saved meal can hold typed-in entries; they stay out of Recent', () async {
      await db.addEntry(MealEntry(date: '2026-10-05', meal: Meal.breakfast, name: 'Sourdough Bread + Egg', grams: 1, servingGrams: 1,
          nutrients: const Nutrients(kcal: 441, protein: 20, carbs: 63, fat: 12)));
      final typed = (await db.entriesOn('2026-10-05')).single;
      await db.saveSavedMeal(SavedMeal(name: 'Usual breakfast', items: [
        SavedMealItem(food: Food(source: FoodSource.manual, name: typed.name, per100g: typed.nutrients.scale(100), servingGrams: 1, servingName: 'serving'), grams: 1),
      ]));
      await db.logSavedMeal('2026-10-06', Meal.breakfast, (await db.savedMeals()).single);
      final again = (await db.entriesOn('2026-10-06')).single;
      expect(again.name, 'Sourdough Bread + Egg');
      expect(again.nutrients.kcal, closeTo(441, 0.01));
      expect(again.servings, 1);
      expect(await db.recentFoods(), isEmpty);
    });

    test('a saved meal logs all its items in one go', () async {
      await db.saveSavedMeal(SavedMeal(name: 'Usual breakfast', items: [
        SavedMealItem(food: ifctFood('B021'), grams: 40),
        SavedMealItem(food: ifct.search('egg').first.food, grams: 100),
      ]));
      final meal = (await db.savedMeals()).single;
      await db.logSavedMeal('2026-10-06', Meal.breakfast, meal);
      expect(await db.entriesOn('2026-10-06'), hasLength(2));
    });

    test('Log screen day: targets from the Coros profile, logged weight and Coros active calories', () async {
      for (final kv in {
        SettingKeys.heightCm: '175.0',
        SettingKeys.corosWeightKg: '78.6',
        SettingKeys.age: '31',
        SettingKeys.gender: 'Male',
      }.entries) {
        await db.setSetting(kv.key, kv.value);
      }
      final sync = CorosSync(db, _NoCoros());
      await db.saveDailyHealth(parseDailyHealth(fixture('coros/daily_health_3d.txt')));

      // A finished day uses Coros's active calories as they are.
      final oct4 = await sync.foodDay(DateTime(2026, 10, 4), now: DateTime(2026, 10, 5, 20));
      expect(oct4.targets!.activeKcal, 987);
      expect(oct4.targets!.dayType.type, DayType.rest); // nothing planned or done in this database

      // Logged weights replace the Coros profile weight.
      await db.saveWeight('2026-10-05', 78.0);
      await db.saveWeight('2026-10-04', 78.4);
      expect(await sync.currentWeight(DateTime(2026, 10, 5)), closeTo(78.2, 0.001));

      // A weight goal applies its deficit.
      await db.saveGoal(Goal(type: GoalType.weight, name: 'Body weight', date: DateTime(2026, 12, 31), targetWeightKg: 72));
      final oct5 = await sync.foodDay(DateTime(2026, 10, 5), now: DateTime(2026, 10, 5, 20));
      expect(oct5.targets!.deficitNote, isNotNull);
      expect(oct5.weight, 78.0);
    });

    test('under-fuelling: a heavy week, low intake on 3+ days, and recovery slipping (PRD F4)', () async {
      for (final kv in {SettingKeys.heightCm: '175.0', SettingKeys.corosWeightKg: '78.6', SettingKeys.age: '31', SettingKeys.gender: 'Male'}.entries) {
        await db.setSetting(kv.key, kv.value);
      }
      final sync = CorosSync(db, FixtureCoros());
      final monday = DateTime(2026, 9, 28);
      await sync.syncWeek(monday, DateTime(2026, 10, 4, 19)); // 3 Excessive load days: a heavy week
      for (final d in ['2026-09-28', '2026-09-29', '2026-09-30']) {
        await db.addEntry(MealEntry(date: d, meal: Meal.lunch, name: 'Small lunch', grams: 1, servingGrams: 1, nutrients: const Nutrients(kcal: 900, protein: 50, carbs: 100, fat: 30)));
      }
      final asOf = DateTime(2026, 10, 4, 19);

      // Recovery held up that week (no short nights, resting HR flat): no flag.
      var review = await sync.weekReviewFromDatabase(monday, asOf: asOf);
      var food = await sync.weekFoodFromDatabase(monday, review, asOf: asOf);
      expect(food.daysLogged, 3);
      expect(food.daysCounted, 7);
      expect(food.kcalDays, 0);
      expect(food.underFuelling, isNull);

      // Resting HR up 4 bpm on the week before: flagged.
      await db.saveRestingHr({for (var i = 0; i < 7; i++) corosDate(monday.add(Duration(days: i))): 56});
      review = await sync.weekReviewFromDatabase(monday, asOf: asOf);
      food = await sync.weekFoodFromDatabase(monday, review, asOf: asOf);
      expect(food.underFuelling, contains('3 logged days under 85%'));
      expect(food.underFuelling, contains('resting HR up'));
    });

    test('without a Coros profile, the Log screen says what is missing', () async {
      final day = await CorosSync(db, _NoCoros()).foodDay(DateTime(2026, 10, 5));
      expect(day.targets, isNull);
      expect(day.missingProfile, 'weight, height, age, sex');
    });
  });
}
