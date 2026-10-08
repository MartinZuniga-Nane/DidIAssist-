import 'package:did_i_attend/src/core/geo_point.dart';
import 'package:did_i_attend/src/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  test('normalizes timestamps to UTC without changing the instant', () {
    final local = DateTime(2026, 10, 5, 9);
    final event = sampleEvent().copyWith(recordedAt: local);
    expect(event.recordedAt.isUtc, isTrue);
    expect(event.recordedAt, local.toUtc());
  });

  test('has value equality and copyWith changes each field', () {
    final event = sampleEvent();
    expectValueEquality(event, sampleEvent(), [
      event.copyWith(id: slotId),
      event.copyWith(type: LocationEventType.geofenceDwell),
      event.copyWith(placeId: () => homeId),
      event.copyWith(
        position: () => GeoPoint(latitude: 51.5007, longitude: -0.1246),
      ),
      event.copyWith(accuracyMeters: () => 30),
      event.copyWith(recordedAt: DateTime.utc(2026, 10, 5, 10)),
    ]);
    expect(event.copyWith(), event);
    final cleared = event.copyWith(
      position: () => null,
      accuracyMeters: () => null,
    );
    expect(cleared.position, isNull);
    expect(cleared.accuracyMeters, isNull);
    expect(cleared.placeId, placeId);
  });

  test('position samples can have no place and no reported accuracy', () {
    final sample = sampleEvent().copyWith(
      type: LocationEventType.positionSample,
      placeId: () => null,
      accuracyMeters: () => null,
    );
    expect(sample.placeId, isNull);
    expect(sample.position, samplePoint());
    expect(sample.accuracyMeters, isNull);
    expect(sample.copyWith(accuracyMeters: () => 0).accuracyMeters, 0);
  });

  test(
    'geofence transitions require a place and samples require a position',
    () {
      for (final type in [
        LocationEventType.geofenceEnter,
        LocationEventType.geofenceExit,
        LocationEventType.geofenceDwell,
      ]) {
        expect(
          () => sampleEvent().copyWith(type: type, placeId: () => null),
          throwsArgumentError,
        );
      }
      expect(
        () => sampleEvent().copyWith(
          type: LocationEventType.positionSample,
          position: () => null,
        ),
        throwsArgumentError,
      );
    },
  );

  test('rejects negative or nonfinite accuracy and blank IDs', () {
    for (final accuracy in [-1.0, double.nan, double.infinity]) {
      expect(
        () => sampleEvent().copyWith(accuracyMeters: () => accuracy),
        throwsArgumentError,
      );
    }
    expect(() => sampleEvent().copyWith(id: ''), throwsArgumentError);
    expect(
      () => sampleEvent().copyWith(placeId: () => ' '),
      throwsArgumentError,
    );
  });
}
