import 'dart:math' as math;
import 'dart:typed_data';

/// A point on a route, in degrees.
class RoutePoint {
  const RoutePoint(this.lat, this.lon);
  final double lat;
  final double lon;

  @override
  bool operator ==(Object other) => other is RoutePoint && other.lat == lat && other.lon == lon;
  @override
  int get hashCode => Object.hash(lat, lon);
}

class FitFormatException implements Exception {
  FitFormatException(this.message);
  final String message;
  @override
  String toString() => 'FIT file unreadable: $message';
}

/// Reads the GPS track from a Coros FIT file: the position of every "record" message
/// (global message 20, fields 0 and 1). Everything else in the file is skipped. Written
/// for the app rather than pulled in as a dependency; checked against a real Coros file
/// (7 Oct 2026: 2,101 records, 2,093 with a position).
List<RoutePoint> readFitTrack(Uint8List bytes) {
  if (bytes.length < 12) throw FitFormatException('too short');
  final headerSize = bytes[0];
  if (headerSize != 12 && headerSize != 14) throw FitFormatException('header size $headerSize');
  if (String.fromCharCodes(bytes.sublist(8, 12)) != '.FIT') throw FitFormatException('no .FIT signature');
  final view = ByteData.sublistView(bytes);
  final dataSize = view.getUint32(4, Endian.little);
  final end = headerSize + dataSize;
  if (end > bytes.length) throw FitFormatException('data size $dataSize past end of file');

  final defs = <int, _Def>{};
  final points = <RoutePoint>[];
  var i = headerSize;
  while (i < end) {
    final header = bytes[i++];
    if (header & 0x80 != 0) {
      // Compressed timestamp header: a data message for local type in bits 5 and 6.
      i = _readData(view, i, defs[(header >> 5) & 0x03], points);
      continue;
    }
    final local = header & 0x0F;
    if (header & 0x40 != 0) {
      // Definition message.
      final bigEndian = bytes[i + 1] == 1;
      final global = view.getUint16(i + 2, bigEndian ? Endian.big : Endian.little);
      final count = bytes[i + 4];
      i += 5;
      final fields = <(int, int)>[];
      for (var f = 0; f < count; f++) {
        fields.add((bytes[i], bytes[i + 1]));
        i += 3;
      }
      var devSize = 0;
      if (header & 0x20 != 0) {
        final devCount = bytes[i++];
        for (var f = 0; f < devCount; f++) {
          devSize += bytes[i + 1];
          i += 3;
        }
      }
      defs[local] = _Def(global, bigEndian, fields, devSize);
    } else {
      i = _readData(view, i, defs[local], points);
    }
  }
  return points;
}

class _Def {
  _Def(this.global, this.bigEndian, this.fields, this.devSize);
  final int global;
  final bool bigEndian;
  final List<(int, int)> fields; // (field number, size in bytes)
  final int devSize;

  int get size => fields.fold(devSize, (s, f) => s + f.$2);
}

const _semicircles = 180 / 2147483648; // 2^31
const _invalidSint32 = 0x7FFFFFFF;

int _readData(ByteData view, int i, _Def? def, List<RoutePoint> points) {
  if (def == null) throw FitFormatException('data message before its definition at byte $i');
  if (def.global == 20) {
    int? lat, lon;
    var at = i;
    final endian = def.bigEndian ? Endian.big : Endian.little;
    for (final (num, size) in def.fields) {
      if (size == 4 && (num == 0 || num == 1)) {
        final v = view.getInt32(at, endian);
        if (v != _invalidSint32) num == 0 ? lat = v : lon = v;
      }
      at += size;
    }
    if (lat != null && lon != null) points.add(RoutePoint(lat * _semicircles, lon * _semicircles));
  }
  return i + def.size;
}

/// Distance in metres (haversine).
double metresBetween(RoutePoint a, RoutePoint b) {
  const r = 6371000.0;
  final dLat = (b.lat - a.lat) * math.pi / 180, dLon = (b.lon - a.lon) * math.pi / 180;
  final h = math.pow(math.sin(dLat / 2), 2) + math.cos(a.lat * math.pi / 180) * math.cos(b.lat * math.pi / 180) * math.pow(math.sin(dLon / 2), 2);
  return 2 * r * math.asin(math.sqrt(h));
}

/// Keeps the route's shape within [toleranceM] metres while dropping most points
/// (Douglas-Peucker). A 1-per-second track of 2,000 points becomes a few hundred.
List<RoutePoint> simplifyRoute(List<RoutePoint> pts, {double toleranceM = 5}) {
  if (pts.length < 3) return List.of(pts);
  // Work in local metres around the first point.
  final lat0 = pts.first.lat * math.pi / 180;
  final xs = [for (final p in pts) (p.lon - pts.first.lon) * 111320 * math.cos(lat0)];
  final ys = [for (final p in pts) (p.lat - pts.first.lat) * 110540];
  final keep = List<bool>.filled(pts.length, false)
    ..[0] = true
    ..[pts.length - 1] = true;
  final stack = <(int, int)>[(0, pts.length - 1)];
  while (stack.isNotEmpty) {
    final (a, b) = stack.removeLast();
    var maxD = 0.0, index = -1;
    final dx = xs[b] - xs[a], dy = ys[b] - ys[a];
    final len = math.sqrt(dx * dx + dy * dy);
    for (var k = a + 1; k < b; k++) {
      final d = len == 0
          ? math.sqrt(math.pow(xs[k] - xs[a], 2) + math.pow(ys[k] - ys[a], 2))
          : ((dy * xs[k] - dx * ys[k] + xs[b] * ys[a] - ys[b] * xs[a]).abs() / len);
      if (d > maxD) {
        maxD = d;
        index = k;
      }
    }
    if (maxD > toleranceM && index > 0) {
      keep[index] = true;
      stack.add((a, index));
      stack.add((index, b));
    }
  }
  return [for (var k = 0; k < pts.length; k++) if (keep[k]) pts[k]];
}

/// Compact storage: 1e-5 degree steps (about 1 m) as varint deltas.
Uint8List encodeRoute(List<RoutePoint> pts) {
  final out = BytesBuilder();
  void varint(int v) {
    var z = v >= 0 ? v << 1 : ((-v) << 1) - 1; // zigzag
    while (z >= 0x80) {
      out.addByte((z & 0x7F) | 0x80);
      z >>= 7;
    }
    out.addByte(z);
  }

  var lat = 0, lon = 0;
  for (final p in pts) {
    final la = (p.lat * 1e5).round(), lo = (p.lon * 1e5).round();
    varint(la - lat);
    varint(lo - lon);
    lat = la;
    lon = lo;
  }
  return out.toBytes();
}

List<RoutePoint> decodeRoute(Uint8List bytes) {
  final pts = <RoutePoint>[];
  var i = 0, lat = 0, lon = 0;
  int varint() {
    var shift = 0, z = 0;
    while (true) {
      final b = bytes[i++];
      z |= (b & 0x7F) << shift;
      if (b < 0x80) break;
      shift += 7;
    }
    return z & 1 == 0 ? z >> 1 : -((z + 1) >> 1);
  }

  while (i < bytes.length) {
    lat += varint();
    lon += varint();
    pts.add(RoutePoint(lat / 1e5, lon / 1e5));
  }
  return pts;
}

/// Splits a route into the parts outside the home privacy zone (PRD F5: route sections
/// inside the zone are hidden on the map; stored data is unchanged).
List<List<RoutePoint>> outsideZone(List<RoutePoint> route, RoutePoint? home, double radiusM) {
  if (home == null || radiusM <= 0) return [route];
  final parts = <List<RoutePoint>>[];
  var current = <RoutePoint>[];
  for (final p in route) {
    if (metresBetween(p, home) <= radiusM) {
      if (current.length >= 2) parts.add(current);
      current = [];
    } else {
      current.add(p);
    }
  }
  if (current.length >= 2) parts.add(current);
  return parts;
}
