import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';

import '../app_controller.dart';
import '../coros/parsers.dart';
import '../map/fit_route.dart';
import '../map/places.dart';
import '../map/places_data.dart';
import '../rules/weekly_review.dart' show formatPace;
import 'food_widgets.dart' show BackSquare, Segmented;
import 'theme.dart';

/// Colour per activity type (PRD F5). Shown with labels in the filter chips, never alone.
Color placeColor(PlaceKind k) => switch (k) {
      PlaceKind.run => Tc.go,
      PlaceKind.trail => Tc.amber,
      PlaceKind.hike => Tc.coral,
      PlaceKind.walk => Tc.sky,
      PlaceKind.ride => Tc.blue,
    };

LatLng _ll(RoutePoint p) => LatLng(p.lat, p.lon);

final _india = LatLngBounds(const LatLng(6.5, 68.0), const LatLng(35.7, 97.4));

/// Dark tiles to match the app (PRD F5). CARTO "Dark Matter" needs a free key since
/// September 2026 (without one every tile is an "API key required" watermark, L50); the key
/// is pasted in Settings. Until then, OpenStreetMap's own tiles, darkened on the phone.
class DarkTiles extends StatelessWidget {
  const DarkTiles({super.key});

  /// Tests can't fetch tiles; they turn this off.
  static bool enabled = true;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();
    final key = AppScope.of(context).mapTilesKey;
    if (key != null && key.isNotEmpty) {
      return TileLayer(
        urlTemplate: 'https://basemaps.cartocdn.com/rastertiles/dark_all/{z}/{x}/{y}{r}.png?key=${Uri.encodeQueryComponent(key)}',
        retinaMode: RetinaMode.isHighDensity(context),
        userAgentPackageName: 'com.trainingcompanion.app',
      );
    }
    return TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.trainingcompanion.app',
      tileBuilder: darkModeTileBuilder,
    );
  }
}

/// "OpenStreetMap contributors", plus CARTO when its tiles are in use.
String tilesAttribution(BuildContext context) =>
    (AppScope.of(context).mapTilesKey ?? '').isEmpty ? 'OpenStreetMap contributors' : 'OpenStreetMap contributors, CARTO';

/// Where a pin is drawn: its start, or the blurred home point inside the privacy zone.
RoutePoint pinPoint(Activity a, HomeZone? zone) {
  final p = RoutePoint(a.startLat!, a.startLon!);
  return zone != null && zone.contains(p) ? zone.blurredCentre : p;
}

/// The Places card on the Week screen (PRD F5): a small map of every run, opening the full map.
class PlacesCard extends StatefulWidget {
  const PlacesCard({super.key});

  @override
  State<PlacesCard> createState() => _PlacesCardState();
}

class _PlacesCardState extends State<PlacesCard> {
  Future<PlacesData>? _future;
  int? _revision;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (_future == null || _revision != app.placesRevision) {
      _revision = app.placesRevision;
      _future = app.screenLoad('Places', () => PlacesData.load(app.db));
    }
    return FutureBuilder<PlacesData>(
      future: _future,
      builder: (context, snap) {
        final data = snap.data;
        if (data == null) {
          return TcCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('PLACES', style: Tc.caps),
              const SizedBox(height: 4),
              Text('Loading your map…', style: Tc.label),
            ]),
          );
        }
        final runs = data.activities.where((a) => placeKindOf(a.sportType) == PlaceKind.run).toList();
        return GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const PlacesScreen())),
          child: TcCard(
            padding: EdgeInsets.zero,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('PLACES', style: Tc.caps),
                      const SizedBox(height: 4),
                      Text(
                        data.activities.isEmpty
                            ? 'Your runs on a map'
                            : '${runs.length} run${runs.length == 1 ? '' : 's'} in ${data.placeCount} place${data.placeCount == 1 ? '' : 's'}',
                        style: Tc.title(18),
                      ),
                    ]),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Tc.textSecondary),
                ]),
              ),
              ClipRRect(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
                child: SizedBox(
                  height: 170,
                  child: IgnorePointer(
                    child: FlutterMap(
                      options: MapOptions(
                        initialCameraFit: CameraFit.bounds(bounds: _india, padding: const EdgeInsets.all(12)),
                        backgroundColor: Tc.background,
                        interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                      ),
                      children: [
                        const DarkTiles(),
                        CircleLayer(circles: [
                          for (final a in runs)
                            CircleMarker(point: _ll(pinPoint(a, data.zone)), radius: 3.5, color: Tc.go, borderColor: Tc.background, borderStrokeWidth: 1),
                        ]),
                      ],
                    ),
                  ),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}

/// The full-screen run map (PRD F5): India or World, clustered pins zoomed out, route lines
/// zoomed in, a filter by type, and the home privacy zone.
class PlacesScreen extends StatefulWidget {
  const PlacesScreen({super.key});

  /// Fetch routes on open; tests can't reach Coros and turn this off.
  static bool syncOnOpen = true;

  @override
  State<PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends State<PlacesScreen> {
  final _map = MapController();
  final LayerHitNotifier<Activity> _hits = ValueNotifier(null);
  Future<PlacesData>? _future;
  int? _revision;
  bool _world = false;
  final _kinds = {PlaceKind.run};
  double _zoom = 4.5;

  /// Route lines show from city zoom; pins of routed activities hide there.
  static const routeZoom = 11.5;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && PlacesScreen.syncOnOpen) AppScope.of(context).syncPlaces();
    });
  }

  List<Activity> _shown(PlacesData d) => d.activities.where((a) => _kinds.contains(placeKindOf(a.sportType))).toList();

  void _frame(PlacesData d, {required bool world}) {
    setState(() => _world = world);
    final shown = _shown(d);
    if (!world || shown.isEmpty) {
      _map.fitCamera(CameraFit.bounds(bounds: _india, padding: const EdgeInsets.all(24)));
      return;
    }
    final pts = [for (final a in shown) _ll(pinPoint(a, d.zone))];
    if (pts.length == 1) {
      _map.move(pts.first, 11);
    } else {
      _map.fitCamera(CameraFit.coordinates(coordinates: pts, padding: const EdgeInsets.fromLTRB(40, 160, 40, 120), maxZoom: 13));
    }
  }

  void _details(Activity a, RoutePoint? routeStart) {
    final km = (a.distanceMeters ?? 0) / 1000;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final d = DateTime.parse(a.date);
    final kind = placeKindOf(a.sportType);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Tc.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (kind != null) Container(width: 10, height: 10, decoration: BoxDecoration(color: placeColor(kind), shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Expanded(child: Text(a.name, style: Tc.title(20))),
            ]),
            const SizedBox(height: 4),
            Text('${d.day} ${months[d.month - 1]} ${d.year}${a.location == null ? '' : ' · ${a.location}'}', style: Tc.label.copyWith(fontSize: 14)),
            const SizedBox(height: 16),
            Wrap(spacing: 24, runSpacing: 12, children: [
              if (km > 0) _stat('Distance', '${km.toStringAsFixed(2)} km'),
              _stat('Time', _duration(a.durationSeconds)),
              if (km > 0 && (kind == PlaceKind.run || kind == PlaceKind.trail)) _stat('Pace', '${formatPace(a.durationSeconds / km)} /km'),
              if (a.avgHr != null) _stat('Avg HR', '${a.avgHr} bpm'),
            ]),
          ]),
        ),
      ),
    );
  }

  static String _duration(int s) => s >= 3600 ? '${s ~/ 3600}:${(s % 3600 ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}' : '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  Widget _stat(String label, String value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Tc.label.copyWith(fontSize: 12)),
        const SizedBox(height: 2),
        Text(value, style: Tc.title(18)),
      ]);

  Future<void> _setHome(LatLng p, PlacesData d) async {
    final app = AppScope.of(context);
    final radius = d.zone?.radiusM ?? PlacesData.defaultRadiusM;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Tc.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text('Set your home zone here?', style: Tc.title(20)),
        content: Text('Route parts within ${radius.round()} m of this point are hidden, and pins inside it aren\'t shown at their real spot. '
            'Your stored data doesn\'t change. Change the radius in Settings.', style: Tc.label.copyWith(fontSize: 14, height: 1.4)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Tc.textSecondary))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Set home zone', style: TextStyle(color: Tc.go))),
        ],
      ),
    );
    if (ok == true) await app.setHomeZone(p.latitude, p.longitude, radius == 0 ? PlacesData.defaultRadiusM : radius);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (_future == null || _revision != app.placesRevision) {
      _revision = app.placesRevision;
      _future = app.screenLoad('Places', () => PlacesData.load(app.db));
    }
    return Scaffold(
      body: FutureBuilder<PlacesData>(
        future: _future,
        builder: (context, snap) {
          final d = snap.data;
          if (d == null) return const Center(child: CircularProgressIndicator(color: Tc.go));
          final shown = _shown(d);
          final routed = _zoom >= routeZoom;
          final lines = <Polyline<Activity>>[
            if (routed)
              for (final a in shown)
                if (d.routes[a.labelId] != null)
                  for (final part in outsideZone(d.routes[a.labelId]!, d.zone?.centre, d.zone?.radiusM ?? 0))
                    Polyline(points: [for (final p in part) _ll(p)], color: placeColor(placeKindOf(a.sportType)!), strokeWidth: 2.5, hitValue: a),
          ];
          final pins = [
            for (final a in shown)
              if (!(routed && d.routes.containsKey(a.labelId)))
                Marker(
                  key: ValueKey(a.labelId),
                  point: _ll(pinPoint(a, d.zone)),
                  width: 18,
                  height: 18,
                  child: Container(
                    decoration: BoxDecoration(
                      color: placeColor(placeKindOf(a.sportType)!),
                      shape: BoxShape.circle,
                      border: Border.all(color: Tc.background, width: 2),
                    ),
                  ),
                ),
          ];
          final byId = {for (final a in shown) a.labelId: a};
          return Stack(children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCameraFit: CameraFit.bounds(bounds: _india, padding: const EdgeInsets.all(24)),
                backgroundColor: Tc.background,
                minZoom: 2,
                maxZoom: 18,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                onPositionChanged: (camera, _) {
                  if ((camera.zoom >= routeZoom) != (_zoom >= routeZoom)) {
                    setState(() => _zoom = camera.zoom);
                  } else {
                    _zoom = camera.zoom;
                  }
                },
                onLongPress: (_, p) => _setHome(p, d),
              ),
              children: [
                const DarkTiles(),
                GestureDetector(
                  onTap: () {
                    final hit = _hits.value;
                    if (hit != null && hit.hitValues.isNotEmpty) _details(hit.hitValues.first, null);
                  },
                  child: PolylineLayer<Activity>(polylines: lines, hitNotifier: _hits, minimumHitbox: 14),
                ),
                MarkerClusterLayerWidget(
                  options: MarkerClusterLayerOptions(
                    markers: pins,
                    maxClusterRadius: 48,
                    size: const Size(40, 40),
                    padding: const EdgeInsets.all(60),
                    onMarkerTap: (m) {
                      final a = byId[(m.key as ValueKey<String>?)?.value];
                      if (a != null) _details(a, null);
                    },
                    builder: (context, markers) => Container(
                      decoration: BoxDecoration(color: Tc.surfaceRaised, shape: BoxShape.circle, border: Border.all(color: Tc.go, width: 2)),
                      alignment: Alignment.center,
                      child: Text('${markers.length}', style: Tc.body.copyWith(fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
                SimpleAttributionWidget(source: Text(tilesAttribution(context)), backgroundColor: const Color(0xCC000000)),
              ],
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const BackSquare(),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Segmented<bool>(values: const [false, true], labels: const ['India', 'World'], selected: _world, onChanged: (w) => _frame(d, world: w)),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final k in PlaceKind.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            avatar: Container(width: 10, height: 10, decoration: BoxDecoration(color: placeColor(k), shape: BoxShape.circle)),
                            label: Text('${k.label} ${d.activities.where((a) => placeKindOf(a.sportType) == k).length}'),
                            selected: _kinds.contains(k),
                            onSelected: (on) => setState(() => on ? _kinds.add(k) : _kinds.remove(k)),
                            showCheckmark: false,
                            selectedColor: Tc.surfaceRaised,
                            backgroundColor: Tc.surface.withValues(alpha: 0.9),
                            labelStyle: TextStyle(fontFamily: Tc.font, fontSize: 13, color: _kinds.contains(k) ? Tc.text : Tc.textSecondary),
                            side: BorderSide(color: _kinds.contains(k) ? placeColor(k) : Tc.hairline),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                          ),
                        ),
                    ]),
                  ),
                ]),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16 + MediaQuery.of(context).padding.bottom,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: BoxDecoration(color: Tc.surface.withValues(alpha: 0.95), borderRadius: BorderRadius.circular(20), border: Border.all(color: Tc.hairline)),
                child: Row(children: [
                  if (app.placesBusy) ...[
                    const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Tc.go)),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      [
                        d.activities.isEmpty
                            ? (app.placesBusy ? 'Loading your activity history…' : 'No activities with GPS yet.')
                            : d.routesDone < d.activities.length
                                ? 'Routes loading: ${d.routesDone} of ${d.activities.length}. More load in the background each day.'
                                : 'All ${d.activities.length} routes loaded.',
                        if (!routed && d.routesDone > 0) 'Zoom in for routes.',
                        if (d.zone != null && d.zone!.radiusM > 0) 'Home zone ${d.zone!.radiusM.round()} m${d.zoneSuggested ? ' (suggested; long-press to move)' : ''}.',
                      ].join(' '),
                      style: Tc.label.copyWith(fontSize: 12, height: 1.35),
                    ),
                  ),
                ]),
              ),
            ),
          ]);
        },
      ),
    );
  }
}
