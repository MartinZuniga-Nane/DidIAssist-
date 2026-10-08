import 'package:did_i_attend/src/domain/location/geofence_registration_id.dart';
import 'package:did_i_attend/src/domain/models/place.dart';
import 'package:native_geofence/native_geofence.dart' as native;

import '../domain/services/fixtures.dart';

native.ActiveGeofence activeGeofence({Place? place, String? registrationId}) {
  final source = place ?? campusPlace();
  return native.ActiveGeofence(
    id: registrationId ?? GeofenceRegistrationId.forPlace(source),
    location: native.Location(
      latitude: source.center.latitude,
      longitude: source.center.longitude,
    ),
    radiusMeters: source.radiusMeters,
    triggers: {native.GeofenceEvent.enter, native.GeofenceEvent.exit},
    androidSettings: null,
  );
}

native.GeofenceCallbackParams callbackParams({
  native.GeofenceEvent event = native.GeofenceEvent.enter,
  List<native.ActiveGeofence>? geofences,
  native.Location? location,
}) => native.GeofenceCallbackParams(
  geofences: geofences ?? [activeGeofence()],
  event: event,
  location: location,
);
