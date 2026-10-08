import 'package:did_i_attend/src/domain/models/location_event_type.dart';
import 'package:did_i_attend/src/platform/native_geofence_mapper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_geofence/native_geofence.dart' as native;

import '../domain/services/fixtures.dart';
import 'fixtures.dart';

void main() {
  const mapper = NativeGeofenceMapper();
  final receipt = DateTime(2026, 10, 5, 9);
  const events = {
    native.GeofenceEvent.enter: LocationEventType.geofenceEnter,
    native.GeofenceEvent.exit: LocationEventType.geofenceExit,
    native.GeofenceEvent.dwell: LocationEventType.geofenceDwell,
  };
  for (final entry in events.entries) {
    test('maps native ${entry.key.name}', () {
      final transition = mapper.map(
        callbackParams(event: entry.key),
        receivedAt: receipt,
      )!;
      expect(transition.type, entry.value);
      expect(transition.placeIds, ['campus']);
      expect(transition.receivedAt, receipt.toUtc());
      expect(transition.fix, isNull);
    });
  }

  test(
    'maps provided device coordinates with unknown accuracy and receipt time',
    () {
      final transition = mapper.map(
        callbackParams(
          location: const native.Location(latitude: 48.8584, longitude: 2.2945),
        ),
        receivedAt: receipt,
      )!;
      expect(transition.fix!.position, eiffelTower());
      expect(transition.fix!.accuracyMeters, isNull);
      expect(transition.fix!.timestamp, receipt.toUtc());
    },
  );

  test('deduplicates place IDs and ignores unrelated native registrations', () {
    final transition = mapper.map(
      callbackParams(
        geofences: [
          activeGeofence(),
          activeGeofence(place: homePlace()),
          activeGeofence(),
          activeGeofence(registrationId: 'other-feature:zone'),
          activeGeofence(registrationId: 'didiattend:v1:malformed'),
        ],
      ),
      receivedAt: receipt,
    )!;
    expect(transition.placeIds, ['campus', 'home']);
  });

  test('empty or entirely unrelated callbacks yield null', () {
    expect(
      mapper.map(callbackParams(geofences: []), receivedAt: receipt),
      isNull,
    );
    expect(
      mapper.map(
        callbackParams(
          geofences: [
            activeGeofence(registrationId: 'unrelated'),
          ],
        ),
        receivedAt: receipt,
      ),
      isNull,
    );
  });

  test('invalid native coordinates retain geofence evidence without a fix', () {
    for (final location in [
      const native.Location(latitude: 91, longitude: 2.2945),
      const native.Location(latitude: 48.8584, longitude: 181),
      const native.Location(latitude: double.nan, longitude: 2.2945),
    ]) {
      final transition = mapper.map(
        callbackParams(location: location),
        receivedAt: receipt,
      )!;
      expect(transition.placeIds, ['campus']);
      expect(transition.fix, isNull);
    }
  });
}
