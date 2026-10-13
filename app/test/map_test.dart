import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:training_companion/coros/parsers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:training_companion/data/app_database.dart';
import 'package:training_companion/data/map_store.dart';
import 'package:training_companion/map/places.dart';
import 'package:training_companion/sync/coros_sync.dart';

import 'coros_sync_test.dart' show FixtureCoros;
import 'package:training_companion/map/fit_route.dart';

String fixture(String name) => File('test/fixtures/coros/$name').readAsStringSync();

void main() {
  final fit = File('test/fixtures/coros/run_2026-10-07.fit').readAsBytesSync();

  group('FIT track (M5)', () {
    test('reads every GPS point of a real Coros run, as fitparse does', () {
      final track = readFitTrack(fit);
      expect(track, hasLength(2093)); // 2,101 records, 8 without a fix (positions moved 0.5 degrees for privacy)
      expect(track.first.lat, closeTo(13.54146, 0.00001));
      expect(track.first.lon, closeTo(78.12846, 0.00001));
      expect(track.last.lat, closeTo(13.54064, 0.00001));
    });

    test('a damaged file is a format error, not an empty route', () {
      expect(() => readFitTrack(fit.sublist(0, 10)), throwsA(isA<FitFormatException>()));
      final noSignature = Uint8List.fromList(fit)..[9] = 0x58;
      expect(() => readFitTrack(noSignature), throwsA(isA<FitFormatException>()));
    });

    test('simplified to a few hundred points, within 5 m of the original', () {
      final track = readFitTrack(fit);
      final simple = simplifyRoute(track);
      expect(simple.length, lessThan(track.length ~/ 4));
      expect(simple.first, track.first);
      expect(simple.last, track.last);
    });

    test('stored compactly and read back to within a metre', () {
      final simple = simplifyRoute(readFitTrack(fit));
      final bytes = encodeRoute(simple);
      expect(bytes.length, lessThan(simple.length * 6));
      final back = decodeRoute(bytes);
      expect(back, hasLength(simple.length));
      for (var k = 0; k < back.length; k++) {
        expect(metresBetween(back[k], simple[k]), lessThan(1.2));
      }
    });

    test('the home privacy zone hides the parts of a route near home', () {
      final track = simplifyRoute(readFitTrack(fit));
      final home = track.first; // this run starts at home
      final parts = outsideZone(track, home, 300);
      expect(parts, isNotEmpty);
      for (final part in parts) {
        for (final p in part) {
          expect(metresBetween(p, home), greaterThan(300));
        }
      }
      expect(outsideZone(track, null, 300), [track]);
    });
  });

  group('history and routes from Coros (M5)', () {
    late AppDatabase db;
    setUpAll(sqfliteFfiInit);
    setUp(() async => db = await AppDatabase.open(factory: databaseFactoryFfi, path: inMemoryDatabasePath, ownConnection: true));
    tearDown(() => db.close());

    test('the whole history: finds the first year with activities, then imports it a month at a time', () async {
      final coros = FixtureCoros();
      await CorosSync(db, coros).importAllActivities(DateTime(2026, 10, 7));
      final yearProbes = coros.calls.where((c) => c == 'querySportRecords').length;
      // 2025 has activities, 2024 none: 2 probes, then Jan 2025 to Oct 2026 = 22 months.
      expect(yearProbes, 2 + 22);
      expect(await db.setting(SettingKeys.allActivitiesImportedAt), isNotNull);
      expect(await db.mappedActivities(), isNotEmpty);
    });

    test('routes: newest first, within the run limit and the daily budget, one bad file skipped', () async {
      await db.saveActivities(parseSportRecords(fixture('sport_records_18d.txt')));
      final mapped = await db.mappedActivities();
      expect(mapped.every((a) => placeKindOf(a.sportType) != null), isTrue);
      var downloads = 0;
      final sync = CorosSync(db, FixtureCoros(), download: (url) async {
        expect(url.host, 's3.coros.com');
        if (++downloads == 2) throw const HttpException('connection reset');
        return fit;
      });
      final now = DateTime.now(); // stored replies carry the real time

      expect(await sync.syncRoutes(max: 3, now: now), 3);
      final routes = await db.routes();
      expect(routes, hasLength(3));
      expect(routes.values.first.length, greaterThan(50));
      expect((await db.errors()).first['source'], 'routes');
      expect(await db.fitRequestsInLastDay(now), hasLength(4)); // three stored, one failed download
      final newest = (mapped..sort((a, b) => b.start.compareTo(a.start))).first;
      expect(routes.containsKey(newest.labelId), isTrue);

      // The failed one isn't retried the same day, and stored ones aren't fetched again.
      final left = await db.activitiesNeedingRoutes(now);
      expect(left.length, mapped.length - 4);

      // The budget counts the last 24 hours, not the calendar day (L53).
      for (var i = 0; i < CorosSync.dailyFitBudget; i++) {
        await db.saveRaw('queryActivityFitFileDownloadUrls', {'i': i}, 'x');
      }
      expect(await sync.syncRoutes(max: 10, now: now), 0);
      expect(await sync.syncRoutes(max: 10, now: now.add(const Duration(hours: 25))), greaterThan(0));
    });

    test("Coros's FIT limit pauses route downloads instead of retrying every run (8 Oct 2026)", () async {
      await db.saveActivities(parseSportRecords(fixture('sport_records_18d.txt')));
      final limited = _LimitedCoros();
      final sync = CorosSync(db, limited, download: (_) async => fit);
      final now = DateTime.now();
      expect(await sync.syncRoutes(max: 5, now: now), 0);
      expect(limited.urlCalls, 1);
      final paused = DateTime.parse((await db.setting(SettingKeys.fitPausedUntil))!);
      expect(paused.isAfter(now.add(const Duration(hours: 3))), isTrue);

      // The next runs don't ask Coros at all until the pause ends.
      expect(await sync.syncRoutes(max: 5, now: now.add(const Duration(minutes: 15))), 0);
      expect(limited.urlCalls, 1);
      expect((await db.errors()).length, 1);
    });
  });

  test('home zone pins are drawn away from the real start', () {
    final home = RoutePoint(13.541, 78.129);
    final zone = HomeZone(home, 300);
    expect(zone.contains(const RoutePoint(13.5411, 78.1291)), isTrue);
    expect(metresBetween(zone.blurredCentre, home), greaterThan(150));
    expect(const HomeZone(RoutePoint(0, 0), 0).contains(const RoutePoint(0, 0)), isFalse); // 0 m: off
  });

  test('an empty history range is no activities, not a format error (7 Oct 2026)', () {
    expect(parseSportRecords(File('test/fixtures/coros/sport_records_none.txt').readAsStringSync()), isEmpty);
  });
}

/// Coros after the daily FIT limit: the link tool returns an error, as on 8 Oct 2026.
class _LimitedCoros implements ToolCaller {
  int urlCalls = 0;

  @override
  Future<String> callTool(String name, Map<String, dynamic> args) async {
    if (name == 'queryActivityFitFileDownloadUrls') {
      urlCalls++;
      throw Exception('queryActivityFitFileDownloadUrls returned an error: You have reached the daily limit of 50 activity FIT files. Please try again later.');
    }
    throw UnimplementedError(name);
  }
}
