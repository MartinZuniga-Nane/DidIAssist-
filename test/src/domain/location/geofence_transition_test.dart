import 'package:did_i_assist/src/domain/location/geofence_transition.dart';
import 'package:did_i_assist/src/domain/location/position_fix.dart';
import 'package:did_i_assist/src/domain/models/location_event_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '../services/fixtures.dart';

void main() {
  final time = DateTime(2026, 10, 5, 9);
  GeofenceTransition transition({
    Iterable<String> ids = const ['home'],
    LocationEventType type = LocationEventType.geofenceEnter,
    DateTime? receivedAt,
    PositionFix? fix,
  }) => GeofenceTransition(
    placeIds: ids,
    type: type,
    receivedAt: receivedAt ?? time,
    fix: fix,
  );

  test('copies and freezes place IDs and normalizes receipt to UTC', () {
    final ids = ['home'];
    final event = transition(ids: ids);
    ids.add('campus');
    expect(event.placeIds, ['home']);
    expect(event.placeIds.clear, throwsUnsupportedError);
    expect(event.receivedAt, time.toUtc());
    expect(event.receivedAt.isUtc, isTrue);
  });

  test('every mapped field participates in value equality', () {
    final original = transition();
    expect(original, transition());
    expect(original.hashCode, transition().hashCode);
    for (final variant in [
      transition(ids: ['campus']),
      transition(type: LocationEventType.geofenceExit),
      transition(receivedAt: time.add(const Duration(seconds: 1))),
      transition(
        fix: PositionFix(position: eiffelTower(), timestamp: time),
      ),
    ]) {
      expect(original, isNot(variant));
    }
  });

  test('rejects position samples and blank IDs but allows empty batches', () {
    expect(
      () => transition(type: LocationEventType.positionSample),
      throwsArgumentError,
    );
    expect(() => transition(ids: ['home', ' ']), throwsArgumentError);
    expect(transition(ids: []).placeIds, isEmpty);
  });
}
