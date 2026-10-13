import 'dart:convert';

import 'package:http/http.dart' as http;

import 'food.dart';

class PackagedSearchUnavailable implements Exception {
  PackagedSearchUnavailable(this.cause);
  final Object cause;
  @override
  String toString() => 'Packaged food search is unavailable right now';
}

/// Packaged foods from Open Food Facts (ODbL), searched online (owner, 5 Oct 2026). Only the
/// search text is sent. Uses the search service at search.openfoodfacts.org; the older
/// /cgi/search.pl was down on 5 Oct 2026.
class OpenFoodFacts {
  OpenFoodFacts({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _fields = 'code,product_name,brands,nutriments,serving_quantity,serving_size';

  Future<List<Food>> search(String query) async {
    final uri = Uri.https('search.openfoodfacts.org', '/search', {'q': query, 'page_size': '25', 'fields': _fields});
    final http.Response res;
    try {
      res = await _client.get(uri, headers: {'User-Agent': 'TrainingCompanion/0.1 (personal Android app)'}).timeout(const Duration(seconds: 12));
    } catch (e) {
      throw PackagedSearchUnavailable(e);
    }
    if (res.statusCode != 200) throw PackagedSearchUnavailable('HTTP ${res.statusCode}');
    try {
      return parseOffSearch(utf8.decode(res.bodyBytes));
    } on FormatException catch (e) {
      throw PackagedSearchUnavailable(e);
    }
  }
}

/// Keeps products with protein, carbs and fat per 100 g. Missing calories are worked out
/// from the macros (4, 4 and 9 kcal per gram).
List<Food> parseOffSearch(String text) {
  final decoded = jsonDecode(text);
  if (decoded is! Map<String, dynamic> || decoded['hits'] is! List) throw const FormatException('no hits in reply');
  final foods = <Food>[];
  for (final hit in (decoded['hits'] as List).whereType<Map<String, dynamic>>()) {
    final name = (hit['product_name'] as String?)?.trim();
    final n = hit['nutriments'];
    if (name == null || name.isEmpty || n is! Map<String, dynamic>) continue;
    double? v(String key) => (n[key] as num?)?.toDouble();
    final p = v('proteins_100g'), c = v('carbohydrates_100g'), f = v('fat_100g');
    if (p == null || c == null || f == null) continue;
    final brands = hit['brands'];
    final brand = brands is List ? brands.whereType<String>().join(', ') : brands as String?;
    final serving = (hit['serving_quantity'] as num?)?.toDouble();
    foods.add(Food(
      source: FoodSource.packaged,
      sourceId: hit['code'] as String?,
      name: name,
      detail: brand == null || brand.isEmpty ? null : brand,
      per100g: Nutrients(kcal: v('energy-kcal_100g') ?? p * 4 + c * 4 + f * 9, protein: p, carbs: c, fat: f, fibre: v('fiber_100g') ?? 0),
      servingGrams: serving != null && serving > 0 ? serving : null,
      servingName: serving != null && serving > 0 ? (hit['serving_size'] as String?) : null,
    ));
  }
  return foods;
}
