import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'food.dart';

/// The Indian Food Composition Tables 2017 (542 foods, per 100 g edible portion), bundled
/// in assets/food so search works offline. They list raw ingredients, not cooked dishes;
/// dishes are built with the recipe builder (owner, 5 Oct 2026).
class Ifct {
  Ifct(this.foods);

  final List<IfctFood> foods;

  static Ifct? _cached;

  /// Everyday spellings IFCT's regional names don't use (it has Arhar and Tuver, not toor).
  static const _aliases = {'toor': 'arhar', 'tur': 'arhar', 'toovar': 'tuvar', 'moong': 'mung', 'chickpea': 'bengal gram'};

  late final Map<String, Food> byCode = {for (final f in foods) f.food.sourceId!: f.food};

  static Future<Ifct> load() async => _cached ??= Ifct.fromJson(await rootBundle.loadString('assets/food/ifct2017.json'));

  factory Ifct.fromJson(String text) {
    final rows = (jsonDecode(text) as Map<String, dynamic>)['foods'] as List;
    return Ifct([for (final r in rows.cast<List>()) IfctFood.fromRow(r)]);
  }

  /// Matches every word of [query] against the English name or the regional names
  /// (so "toor" finds Red gram, dal). Names starting with the query come first.
  List<IfctFood> search(String query, {int limit = 40}) {
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).map((w) => _aliases[w] ?? w).toList();
    if (words.isEmpty) return [];
    final scored = <(int, IfctFood)>[];
    for (final f in foods) {
      final name = f.food.name.toLowerCase();
      final local = f.local.toLowerCase();
      if (!words.every((w) => name.contains(w) || local.contains(w))) continue;
      final score = name.startsWith(words.first)
          ? 0
          : words.every(name.contains)
              ? 1
              : 2;
      scored.add((score, f));
    }
    scored.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.food.name.length.compareTo(b.$2.food.name.length));
    return [for (final s in scored.take(limit)) s.$2];
  }
}

class IfctFood {
  IfctFood(this.food, this.local);

  final Food food;

  /// Regional names, e.g. "H. Arhar dal; Tam. Thuvaram paruppu".
  final String local;

  factory IfctFood.fromRow(List r) => IfctFood(
        Food(
          source: FoodSource.ifct,
          sourceId: r[0] as String,
          name: r[1] as String,
          detail: r[2] as String,
          per100g: Nutrients(
            kcal: (r[4] as num).toDouble(),
            protein: (r[5] as num).toDouble(),
            carbs: (r[6] as num).toDouble(),
            fat: (r[7] as num).toDouble(),
            fibre: (r[8] as num).toDouble(),
          ),
        ),
        r[3] as String,
      );
}
