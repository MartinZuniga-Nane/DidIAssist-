import 'dart:math' as math;

import 'package:did_i_attend/src/core/geo_point.dart';

const _earthRadiusMeters = 6371008.8;

double haversineDistanceMeters(GeoPoint from, GeoPoint to) {
  final fromLatitude = _radians(from.latitude);
  final toLatitude = _radians(to.latitude);
  final latitudeDelta = toLatitude - fromLatitude;
  final longitudeDelta = _radians(to.longitude - from.longitude);
  final latitudeSine = math.sin(latitudeDelta / 2);
  final longitudeSine = math.sin(longitudeDelta / 2);
  final a =
      latitudeSine * latitudeSine +
      math.cos(fromLatitude) *
          math.cos(toLatitude) *
          longitudeSine *
          longitudeSine;
  // Roundoff at antipodal points can put a just outside [0, 1].
  final clamped = a.clamp(0.0, 1.0);
  return 2 *
      _earthRadiusMeters *
      math.atan2(math.sqrt(clamped), math.sqrt(1 - clamped));
}

double _radians(double degrees) => degrees * math.pi / 180;
