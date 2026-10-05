import 'package:did_i_assist/src/core/geo_point.dart';
import 'package:did_i_assist/src/domain/location/geofence_registration_id.dart';
import 'package:did_i_assist/src/domain/location/geofence_transition.dart';
import 'package:did_i_assist/src/domain/location/position_fix.dart';
import 'package:did_i_assist/src/domain/models/location_event_type.dart';
import 'package:native_geofence/native_geofence.dart' as native;

final class NativeGeofenceMapper {
  const NativeGeofenceMapper();

  GeofenceTransition? map(
    native.GeofenceCallbackParams params, {
    required DateTime receivedAt,
  }) {
    final placeIds = params.geofences
        .map((geofence) => GeofenceRegistrationId.placeIdFrom(geofence.id))
        .whereType<String>()
        .toSet();
    if (placeIds.isEmpty) return null;
    PositionFix? fix;
    final location = params.location;
    if (location != null &&
        location.latitude.isFinite &&
        location.longitude.isFinite &&
        location.isValid) {
      // This plugin version supplies neither device accuracy nor fix timestamp.
      fix = PositionFix(
        position: GeoPoint(
          latitude: location.latitude,
          longitude: location.longitude,
        ),
        timestamp: receivedAt,
      );
    }
    return GeofenceTransition(
      placeIds: placeIds,
      type: switch (params.event) {
        native.GeofenceEvent.enter => LocationEventType.geofenceEnter,
        native.GeofenceEvent.exit => LocationEventType.geofenceExit,
        native.GeofenceEvent.dwell => LocationEventType.geofenceDwell,
      },
      fix: fix,
      receivedAt: receivedAt,
    );
  }
}
