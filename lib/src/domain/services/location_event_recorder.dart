import 'package:did_i_assist/src/domain/location/background_location_handler.dart';
import 'package:did_i_assist/src/domain/location/geofence_transition.dart';
import 'package:did_i_assist/src/domain/location/position_fix.dart';
import 'package:did_i_assist/src/domain/models/location_event.dart';
import 'package:did_i_assist/src/domain/models/location_event_type.dart';
import 'package:did_i_assist/src/domain/repositories/location_event_repository.dart';
import 'package:uuid/uuid.dart';

final class LocationEventRecorder implements BackgroundLocationHandler {
  LocationEventRecorder({
    required LocationEventRepository repository,
    String Function()? generateId,
  }) : _repository = repository,
       _generateId = generateId ?? _uuidV4;

  final LocationEventRepository _repository;
  final String Function() _generateId;

  static String _uuidV4() => const Uuid().v4();

  Future<List<LocationEvent>> recordGeofenceTransition({
    required Iterable<String> placeIds,
    required LocationEventType type,
    required DateTime receivedAt,
    PositionFix? fix,
  }) async {
    final transition = GeofenceTransition(
      placeIds: placeIds,
      type: type,
      receivedAt: receivedAt,
      fix: fix,
    );
    final recordedAt =
        fix != null && !fix.timestamp.isAfter(transition.receivedAt)
        ? fix.timestamp
        : transition.receivedAt;
    final events = [
      for (final placeId in transition.placeIds.toSet())
        LocationEvent(
          id: _generateId(),
          type: type,
          placeId: placeId,
          position: fix?.position,
          accuracyMeters: fix?.accuracyMeters,
          recordedAt: recordedAt,
        ),
    ];
    for (final event in events) {
      await _repository.append(event);
    }
    return events;
  }

  Future<LocationEvent> recordPositionSample(PositionFix fix) async {
    final event = LocationEvent(
      id: _generateId(),
      type: LocationEventType.positionSample,
      position: fix.position,
      accuracyMeters: fix.accuracyMeters,
      recordedAt: fix.timestamp,
    );
    await _repository.append(event);
    return event;
  }

  @override
  Future<void> handle(GeofenceTransition transition) async {
    await recordGeofenceTransition(
      placeIds: transition.placeIds,
      type: transition.type,
      receivedAt: transition.receivedAt,
      fix: transition.fix,
    );
  }
}
