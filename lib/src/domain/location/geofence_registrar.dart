import 'package:did_i_assist/src/domain/models/place.dart';

abstract interface class GeofenceRegistrar {
  /// OS registration IDs, including geofences owned by other features.
  Future<Set<String>> registeredIds();

  Future<void> register(Place place);

  /// Removes an OS registration ID returned by [registeredIds].
  Future<void> unregister(String registrationId);
}
