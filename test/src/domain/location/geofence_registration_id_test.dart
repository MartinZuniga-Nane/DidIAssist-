import 'dart:convert';
import 'dart:typed_data';

import 'package:did_i_assist/src/domain/location/geofence_registration_id.dart';
import 'package:did_i_assist/src/domain/models/place_kind.dart';
import 'package:flutter_test/flutter_test.dart';

import '../services/fixtures.dart';

void main() {
  test('round trips arbitrary escaped place IDs deterministically', () {
    for (final id in ['home', 'zone:with/slash%', 'public landmark ☀']) {
      final place = homePlace(id: id);
      final encoded = GeofenceRegistrationId.forPlace(place);
      expect(GeofenceRegistrationId.placeIdFrom(encoded), id);
      expect(GeofenceRegistrationId.forPlace(place), encoded);
    }
  });

  test('UUID registration IDs fit the Android 100-character limit', () {
    final place = homePlace(id: '11111111-1111-4111-8111-111111111111');
    expect(
      GeofenceRegistrationId.forPlace(place).length,
      lessThanOrEqualTo(100),
    );
  });

  test('fingerprint changes only when center or radius changes', () {
    final place = homePlace();
    final id = GeofenceRegistrationId.forPlace(place);
    expect(
      GeofenceRegistrationId.forPlace(place.copyWith(name: 'Renamed')),
      id,
    );
    expect(
      GeofenceRegistrationId.forPlace(place.copyWith(kind: PlaceKind.campus)),
      id,
    );
    for (final changed in [
      place.copyWith(radiusMeters: 151),
      place.copyWith(center: place.center.copyWith(latitude: 48.8585)),
      place.copyWith(center: place.center.copyWith(longitude: 2.2946)),
    ]) {
      expect(GeofenceRegistrationId.forPlace(changed), isNot(id));
    }
  });

  test('ignores unrelated, malformed and invalid geometry IDs', () {
    for (final id in [
      'home',
      'another-feature:zone',
      'didiassist:v2:home:geometry',
      'didiassist:v1:',
      'didiassist:v1:home:bad',
      'didiassist:v1:%:bad',
      'didiassist:v1:home:bad:extra',
    ]) {
      expect(GeofenceRegistrationId.placeIdFrom(id), isNull);
    }
    for (final (latitude, radius) in [
      (91.0, 150.0),
      (48.8584, 99.0),
      (double.nan, 150.0),
    ]) {
      final data = ByteData(24)
        ..setFloat64(0, latitude)
        ..setFloat64(8, 2.2945)
        ..setFloat64(16, radius);
      final fingerprint = base64Url.encode(data.buffer.asUint8List());
      expect(
        GeofenceRegistrationId.placeIdFrom('didiassist:v1:home:$fingerprint'),
        isNull,
      );
      expect(
        GeofenceRegistrationId.placeIdFrom('didiassist:v1:%20:$fingerprint'),
        isNull,
      );
    }
  });
}
