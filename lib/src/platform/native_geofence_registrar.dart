import 'package:did_i_attend/src/domain/location/geofence_registrar.dart';
import 'package:did_i_attend/src/domain/location/geofence_registration_id.dart';
import 'package:did_i_attend/src/domain/models/place.dart';
import 'package:did_i_attend/src/platform/background_location_callback.dart';
import 'package:native_geofence/native_geofence.dart' as native;

final class NativeGeofenceRegistrar implements GeofenceRegistrar {
  /// A top-level bootstrap callback can register the handler in a fresh isolate
  /// before delegating to [nativeGeofenceCallback].
  NativeGeofenceRegistrar({
    native.NativeGeofenceManager? manager,
    Future<void> Function(native.GeofenceCallbackParams) callback =
        nativeGeofenceCallback,
  }) : _manager = manager ?? native.NativeGeofenceManager.instance,
       _callback = callback;

  final native.NativeGeofenceManager _manager;
  final Future<void> Function(native.GeofenceCallbackParams) _callback;
  Future<void>? _initialization;

  Future<void> _ensureInitialized() async {
    try {
      await (_initialization ??= _manager.initialize());
    } on Exception {
      _initialization = null;
      rethrow;
    }
  }

  @override
  Future<Set<String>> registeredIds() async {
    await _ensureInitialized();
    return (await _manager.getRegisteredGeofenceIds()).toSet();
  }

  @override
  Future<void> register(Place place) async {
    await _ensureInitialized();
    await _manager.createGeofence(
      native.Geofence(
        id: GeofenceRegistrationId.forPlace(place),
        location: native.Location(
          latitude: place.center.latitude,
          longitude: place.center.longitude,
        ),
        radiusMeters: place.radiusMeters,
        triggers: {
          native.GeofenceEvent.enter,
          native.GeofenceEvent.exit,
          native.GeofenceEvent.dwell,
        },
        iosSettings: const native.IosGeofenceSettings(initialTrigger: true),
        androidSettings: const native.AndroidGeofenceSettings(
          initialTriggers: {native.GeofenceEvent.enter},
          loiteringDelay: Duration(minutes: 2),
          notificationResponsiveness: Duration(minutes: 2),
        ),
      ),
      _callback,
    );
  }

  @override
  Future<void> unregister(String registrationId) async {
    if (GeofenceRegistrationId.placeIdFrom(registrationId) == null) return;
    await _ensureInitialized();
    await _manager.removeGeofenceById(registrationId);
  }
}
