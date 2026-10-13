import '../coros/parsers.dart';
import '../data/app_database.dart';
import '../data/map_store.dart';
import '../rules/weekly_review.dart' show homePoint;
import '../sync/coros_sync.dart';
import 'fit_route.dart';
import 'places.dart';

/// Everything the Places card and the run map draw, from stored data (works offline).
class PlacesData {
  PlacesData({required this.activities, required this.routes, required this.zone, required this.zoneSuggested});

  /// Activities with a start point, newest first.
  final List<Activity> activities;
  final Map<String, List<RoutePoint>> routes;

  /// The home privacy zone; null only when there is no history to suggest one from.
  final HomeZone? zone;

  /// True when the zone is the app's suggestion (the most common start), not one the user set.
  final bool zoneSuggested;

  int get routesDone => activities.where((a) => routes.containsKey(a.labelId)).length;

  /// Distinct places, by the Coros location name ("Bangalore Run" and "Bangalore Walk" are one).
  int get placeCount => activities.map((a) => (a.location ?? '').replaceAll(RegExp(r'\s+(Run|Walk|Hike|Ride|Trail Run)$'), '')).toSet().length;

  static const defaultRadiusM = 300.0;

  static Future<PlacesData> load(AppDatabase db) async {
    final activities = await db.mappedActivities()
      ..sort((a, b) => b.start.compareTo(a.start));
    final lat = double.tryParse(await db.setting(SettingKeys.homeZoneLat) ?? '');
    final lon = double.tryParse(await db.setting(SettingKeys.homeZoneLon) ?? '');
    final radius = double.tryParse(await db.setting(SettingKeys.homeZoneRadiusM) ?? '') ?? defaultRadiusM;
    HomeZone? zone;
    var suggested = false;
    if (lat != null && lon != null) {
      zone = HomeZone(RoutePoint(lat, lon), radius);
    } else {
      // PRD F5: the app suggests the most common start point.
      final home = homePoint(activities);
      if (home != null) {
        zone = HomeZone(RoutePoint(home.$1, home.$2), radius);
        suggested = true;
      }
    }
    return PlacesData(activities: activities, routes: await db.routes(), zone: zone, zoneSuggested: suggested);
  }
}
