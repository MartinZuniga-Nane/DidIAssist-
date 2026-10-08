import 'package:did_i_attend/src/core/geo_point.dart';
import 'package:did_i_attend/src/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  test('defaults to a 150 meter radius', () {
    expect(samplePlace().radiusMeters, 150);
  });

  test('has value equality and copyWith changes each field', () {
    final place = samplePlace();
    expectValueEquality(place, samplePlace(), [
      place.copyWith(id: homeId),
      place.copyWith(name: 'Home'),
      place.copyWith(kind: PlaceKind.home),
      place.copyWith(center: GeoPoint(latitude: 51.5007, longitude: -0.1246)),
      place.copyWith(radiusMeters: 200),
    ]);
    expect(place.copyWith(), place);
    expect(place.copyWith(name: 'Home').center, place.center);
  });

  test('accepts both radius boundaries and rejects invalid radii', () {
    expect(samplePlace().copyWith(radiusMeters: 100).radiusMeters, 100);
    expect(samplePlace().copyWith(radiusMeters: 1000).radiusMeters, 1000);
    for (final radius in [99.99, 1000.01, double.nan, double.infinity]) {
      expect(
        () => samplePlace().copyWith(radiusMeters: radius),
        throwsArgumentError,
      );
    }
  });

  test('rejects blank IDs and names', () {
    expect(() => samplePlace().copyWith(id: ''), throwsArgumentError);
    expect(() => samplePlace().copyWith(name: '  '), throwsArgumentError);
  });
}
