import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../coros/parsers.dart';
import '../map/fit_route.dart';
import '../map/places.dart';
import 'app_database.dart';

/// Reads and writes for the run map (M5). The routes table is created in app_database.dart.
extension MapStore on AppDatabase {
  Future<List<Activity>> mappedActivities() async => (await activitiesBetween('2000-01-01', '2999-12-31')).where(isMapped).toList();

  /// GPS activities without a route yet, newest first. A failed download is retried after
  /// a week, not on every run.
  Future<List<Activity>> activitiesNeedingRoutes(DateTime now) async {
    final retryBefore = now.subtract(const Duration(days: 7)).toIso8601String();
    final skip = {
      for (final r in await db.query('routes', columns: ['label_id'], where: 'error IS NULL OR fetched_at > ?', whereArgs: [retryBefore]))
        r['label_id'] as String,
    };
    final all = await mappedActivities();
    all.sort((a, b) => b.start.compareTo(a.start));
    return all.where((a) => !skip.contains(a.labelId)).toList();
  }

  Future<void> saveRoute(String labelId, List<RoutePoint> points) => db.insert(
        'routes',
        {'label_id': labelId, 'points': encodeRoute(points), 'point_count': points.length, 'fetched_at': DateTime.now().toIso8601String(), 'error': null},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> saveRouteError(String labelId, String error) => db.insert(
        'routes',
        {'label_id': labelId, 'points': null, 'point_count': 0, 'fetched_at': DateTime.now().toIso8601String(), 'error': error},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<Map<String, List<RoutePoint>>> routes() async => {
        for (final r in await db.query('routes', where: 'points IS NOT NULL'))
          r['label_id'] as String: decodeRoute(r['points'] as Uint8List),
      };

  /// FIT links fetched in the 24 hours before [now], oldest first. Coros's limit of 50 is a
  /// rolling 24 hours, not a calendar day (L53), so the app counts the same way, from the
  /// replies it stored.
  Future<List<DateTime>> fitRequestsInLastDay(DateTime now) async => [
        for (final r in await db.query('raw_replies',
            columns: ['fetched_at'],
            where: "tool = 'queryActivityFitFileDownloadUrls' AND fetched_at > ?",
            whereArgs: [now.toUtc().subtract(const Duration(hours: 24)).toIso8601String()],
            orderBy: 'fetched_at'))
          DateTime.parse(r['fetched_at'] as String),
      ];

  /// FIT downloads used on [day] (yyyy-MM-dd), against the daily budget.
  Future<int> fitDownloadsOn(String day) async {
    final v = (await setting('fit_downloads') ?? '').split('|');
    return v.length == 2 && v[0] == day ? int.tryParse(v[1]) ?? 0 : 0;
  }

  Future<int> addFitDownload(String day) async {
    final n = await fitDownloadsOn(day) + 1;
    await setSetting('fit_downloads', '$day|$n');
    return n;
  }
}
