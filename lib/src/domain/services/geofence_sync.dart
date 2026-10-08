import 'package:did_i_attend/src/domain/location/geofence_registrar.dart';
import 'package:did_i_attend/src/domain/location/geofence_registration_id.dart';
import 'package:did_i_attend/src/domain/repositories/place_repository.dart';

final class GeofenceSync {
  const GeofenceSync({
    required PlaceRepository placeRepository,
    required GeofenceRegistrar registrar,
  }) : _places = placeRepository,
       _registrar = registrar;

  final PlaceRepository _places;
  final GeofenceRegistrar _registrar;

  Future<void> sync() async {
    final places = await _places.getAll();
    final desired = {
      for (final place in places) GeofenceRegistrationId.forPlace(place): place,
    };
    final registered = await _registrar.registeredIds();
    final obsolete =
        registered
            .where(
              (id) =>
                  GeofenceRegistrationId.placeIdFrom(id) != null &&
                  !desired.containsKey(id),
            )
            .toList()
          ..sort();
    for (final id in obsolete) {
      await _registrar.unregister(id);
    }
    final missing =
        desired.keys.where((id) => !registered.contains(id)).toList()..sort();
    for (final id in missing) {
      await _registrar.register(desired[id]!);
    }
  }
}
