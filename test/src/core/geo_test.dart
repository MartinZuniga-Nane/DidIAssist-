import 'dart:math' as math;

import 'package:did_i_attend/src/core/geo.dart';
import 'package:did_i_attend/src/core/geo_point.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final eiffelTower = GeoPoint(latitude: 48.8584, longitude: 2.2945);
  final bigBen = GeoPoint(latitude: 51.5007, longitude: -0.1246);

  test('identical points have zero distance', () {
    expect(haversineDistanceMeters(eiffelTower, eiffelTower), 0);
  });

  test('Eiffel Tower to Big Ben is approximately 341 km', () {
    expect(haversineDistanceMeters(eiffelTower, bigBen), closeTo(341000, 1000));
    expect(
      haversineDistanceMeters(bigBen, eiffelTower),
      closeTo(haversineDistanceMeters(eiffelTower, bigBen), 0.000001),
    );
  });

  test('an antipodal point is half an Earth circumference away', () {
    final antipode = GeoPoint(
      latitude: -eiffelTower.latitude,
      longitude: eiffelTower.longitude - 180,
    );
    expect(
      haversineDistanceMeters(eiffelTower, antipode),
      closeTo(math.pi * 6371008.8, 1),
    );
  });

  test('longitude does not affect distance at the geographic North Pole', () {
    final pole = GeoPoint(latitude: 90, longitude: 0);
    final samePole = GeoPoint(latitude: 90, longitude: 180);
    expect(haversineDistanceMeters(pole, samePole), closeTo(0, 0.000001));
  });

  test('distance is stable across the antimeridian', () {
    final crossingFrom = GeoPoint(latitude: 0, longitude: 179.9);
    final crossingTo = GeoPoint(latitude: 0, longitude: -179.9);
    expect(
      haversineDistanceMeters(crossingFrom, crossingTo),
      closeTo(22239.016, 0.01),
    );
  });
}
