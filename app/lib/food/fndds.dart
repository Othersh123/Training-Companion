import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'food.dart';

/// USDA FNDDS survey foods (5,431, public domain): cooked dishes and fruits with household
/// portions ("1 fruit", "1 medium chappatti"). Used to estimate values for a manual entry
/// when you don't know them (owner, 5 Oct 2026). US recipes, so always labelled an estimate.
class Fndds {
  Fndds(this.foods);

  final List<FnddsFood> foods;

  static Fndds? _cached;

  static Future<Fndds> load() async => _cached ??= Fndds.fromJson(await rootBundle.loadString('assets/food/fndds.json'));

  factory Fndds.fromJson(String text) {
    final rows = (jsonDecode(text) as Map<String, dynamic>)['foods'] as List;
    return Fndds([for (final r in rows.cast<List>()) FnddsFood.fromRow(r)]);
  }

  late final Map<String, FnddsFood> byName = {for (final f in foods) f.name: f};

  /// Everyday words to FNDDS spellings ("roti" would otherwise also find rotisserie chicken).
  static const _aliases = {
    'chapati': 'chappatti',
    'chapathi': 'chappatti',
    'roti': 'chappatti',
    'phulka': 'chappatti',
    'curd': 'yogurt',
    'dahi': 'yogurt',
    'yoghurt': 'yogurt',
    'channa': 'chickpeas',
    'chana': 'chickpeas',
    'chole': 'chickpeas',
    'dhal': 'dal',
    'daal': 'dal',
    // USDA names plain tofu "Soybean curd" and files sourdough under French bread (5 Oct 2026).
    'tofu': 'soybean curd',
    'sourdough': 'french',
  };

  /// Every word must start a word in the name. Whole-word matches and shorter names first,
  /// so "guava" puts "Guava, raw" above "Guava nectar".
  List<FnddsFood> search(String query, {int limit = 6}) {
    final words = query
        .toLowerCase()
        .split(RegExp(r'[\s,]+'))
        .where((w) => w.length > 1)
        .expand((w) => (_aliases[w] ?? w).split(' '))
        .toSet()
        .toList();
    if (words.isEmpty) return [];
    final all = _match(words, limit);
    if (all.isNotEmpty || words.length == 1) return all;
    // "sourdough bread" has no exact match: fall back to the last word, then the others.
    for (final w in words.reversed) {
      final some = _match([w], limit);
      if (some.isNotEmpty) return some;
    }
    return [];
  }

  List<FnddsFood> _match(List<String> words, int limit) {
    final scored = <(int, FnddsFood)>[];
    for (final f in foods) {
      final nameWords = f.lower.split(RegExp(r'[^a-z0-9]+'));
      if (!words.every((w) => nameWords.any((n) => n.startsWith(w)))) continue;
      var score = f.name.length;
      if (words.every(nameWords.contains)) score -= 1000;
      if (nameWords.first.startsWith(words.first)) score -= 500;
      // "Rice, white, cooked" (the food itself) before "Rice milk" or "Rice pilaf".
      if (f.lower.split(',').first.trim() == words.first) score -= 300;
      if (f.lower.contains('raw') || f.lower.contains('cooked')) score -= 50; // plain food before juices and pastes
      if (f.lower.endsWith(', nfs')) score -= 40; // USDA's generic version ("Rice, cooked, NFS")
      if (f.portions.isEmpty) score += 200;
      scored.add((score, f));
    }
    scored.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final s in scored.take(limit)) s.$2];
  }

  /// "Rice + chapati", "bread and egg" -> the separate foods to estimate.
  static List<String> parts(String name) =>
      name.split(RegExp(r'\s*(?:\+|&|/|,|\band\b|\bwith\b)\s*', caseSensitive: false)).map((p) => p.trim()).where((p) => p.length >= 2).toList();
}

class FnddsFood {
  FnddsFood(this.name, this.per100g, this.portions) : lower = name.toLowerCase();

  final String name;
  final String lower;
  final Nutrients per100g;

  /// Household measures, e.g. ("1 fruit", 55). Always followed by 100 g in the picker.
  final List<(String, double)> portions;

  /// The portion to start with: a whole item ("1 fruit", "1 medium", "1 egg") over a slice
  /// or a tablespoon, else the first listed, else 100 g.
  (String, double) get defaultPortion {
    const whole = ['medium', 'fruit', 'item', 'piece', 'regular'];
    final first = name.toLowerCase().split(RegExp(r'[^a-z]+')).first;
    for (final w in [...whole, first]) {
      final p = portions.where((p) => p.$1.toLowerCase().contains(w) && !p.$1.contains('slice')).firstOrNull;
      if (p != null) return p;
    }
    return portions.where((p) => !p.$1.contains('slice') && !p.$1.contains('tablespoon')).firstOrNull ?? portions.firstOrNull ?? ('100 g', 100);
  }

  /// As a loggable food, starting on its whole-item portion.
  Food toFood() {
    final p = defaultPortion;
    return Food(
      source: FoodSource.usda,
      sourceId: name,
      name: name,
      detail: 'USDA estimate',
      per100g: per100g,
      servingGrams: p.$2,
      servingName: p.$1,
      portions: [...portions, ('100 g', 100)],
    );
  }

  factory FnddsFood.fromRow(List r) => FnddsFood(
        r[0] as String,
        Nutrients(
          kcal: (r[1] as num).toDouble(),
          protein: (r[2] as num).toDouble(),
          carbs: (r[3] as num).toDouble(),
          fat: (r[4] as num).toDouble(),
          fibre: (r[5] as num).toDouble(),
        ),
        [for (final p in (r[6] as List).cast<List>()) (p[0] as String, (p[1] as num).toDouble())],
      );
}

/// Calories implied by the macros (4, 4 and 9 kcal per gram).
double kcalFromMacros(double protein, double carbs, double fat) => protein * 4 + carbs * 4 + fat * 9;

/// True when typed calories and macros disagree by more than 25% (and 60 kcal), as with
/// "600 kcal, 600 g carbs" (5 Oct 2026). Alcohol and rounding make small gaps normal.
bool macrosDisagree(double kcal, double protein, double carbs, double fat) {
  final implied = kcalFromMacros(protein, carbs, fat);
  final gap = (implied - kcal).abs();
  return gap > 60 && gap > kcal * 0.25;
}
