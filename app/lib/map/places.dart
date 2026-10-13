import '../coros/parsers.dart';
import 'fit_route.dart';

/// The activity types on the run map (PRD F5). Each has its own colour; runs show by default.
enum PlaceKind { run, trail, hike, walk, ride }

extension PlaceKindLabel on PlaceKind {
  String get label => switch (this) {
        PlaceKind.run => 'Runs',
        PlaceKind.trail => 'Trail runs',
        PlaceKind.hike => 'Hikes',
        PlaceKind.walk => 'Walks',
        PlaceKind.ride => 'Rides',
      };
}

/// Coros sport codes (querySportRecords' list): runs 100, 101 and 103; trail 102; hike and
/// mountain climb 104 and 105; walk 900; bikes 200 to 205 and 299. Other sports, and any
/// activity without a start point (pool, gym, treadmill), aren't on the map.
PlaceKind? placeKindOf(int sportType) => switch (sportType) {
      100 || 101 || 103 => PlaceKind.run,
      102 => PlaceKind.trail,
      104 || 105 => PlaceKind.hike,
      900 => PlaceKind.walk,
      >= 200 && <= 205 || 299 => PlaceKind.ride,
      _ => null,
    };

bool isMapped(Activity a) => a.startLat != null && a.startLon != null && placeKindOf(a.sportType) != null;

/// The home privacy zone (PRD F5). [radiusM] 0 means off.
class HomeZone {
  const HomeZone(this.centre, this.radiusM);
  final RoutePoint centre;
  final double radiusM;

  bool contains(RoutePoint p) => radiusM > 0 && metresBetween(p, centre) <= radiusM;

  /// Where pins inside the zone are drawn instead of their real start: a point a fixed
  /// distance and bearing from home, so the map never shows the exact spot.
  RoutePoint get blurredCentre => RoutePoint(centre.lat + radiusM * 0.6 / 110540, centre.lon - radiusM * 0.45 / 111320);
}
