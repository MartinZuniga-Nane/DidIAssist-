import 'package:did_i_attend/src/core/geo_point.dart';
import 'package:flutter_test/flutter_test.dart';

GeoPoint samplePoint() => GeoPoint(latitude: 48.8584, longitude: 2.2945);

void main() {
  test('has value equality and copyWith preserves unchanged coordinates', () {
    final point = samplePoint();
    expect(point, samplePoint());
    expect(point.hashCode, samplePoint().hashCode);
    expect(point.copyWith(latitude: 51.5007), isNot(point));
    expect(point.copyWith(longitude: -0.1246), isNot(point));
    expect(point.copyWith(), point);
    expect(point.copyWith(latitude: 51.5007).longitude, point.longitude);
  });

  test('accepts coordinate boundaries', () {
    expect(GeoPoint(latitude: -90, longitude: -180).latitude, -90);
    expect(GeoPoint(latitude: 90, longitude: 180).longitude, 180);
  });

  test(
    'rejects out-of-range and nonfinite coordinates in all entry points',
    () {
      for (final latitude in [-90.01, 90.01, double.nan, double.infinity]) {
        expect(
          () => GeoPoint(latitude: latitude, longitude: 0),
          throwsArgumentError,
        );
        expect(
          () => samplePoint().copyWith(latitude: latitude),
          throwsArgumentError,
        );
      }
      for (final longitude in [
        -180.01,
        180.01,
        double.nan,
        double.negativeInfinity,
      ]) {
        expect(
          () => GeoPoint(latitude: 0, longitude: longitude),
          throwsArgumentError,
        );
      }
    },
  );
}
