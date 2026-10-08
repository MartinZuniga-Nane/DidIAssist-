import 'package:did_i_attend/src/core/local_date.dart';
import 'package:did_i_attend/src/domain/models/location_event.dart';
import 'package:did_i_attend/src/domain/models/location_event_type.dart';
import 'package:did_i_attend/src/domain/models/place.dart';
import 'package:did_i_attend/src/domain/models/place_kind.dart';
import 'package:did_i_attend/src/domain/models/trip.dart';

final class TripDetector {
  const TripDetector();

  List<Trip> detect({
    required Iterable<LocationEvent> events,
    required Iterable<Place> places,
  }) {
    final placesById = {for (final place in places) place.id: place};
    final transitions =
        events
            .where((event) => event.type != LocationEventType.positionSample)
            .toList()
          ..sort(_compareEvents);
    final trips = <Trip>[];
    LocationEvent? departure;
    for (final event in transitions) {
      final place = placesById[event.placeId];
      if (place == null) continue;
      if (place.kind == PlaceKind.home) {
        if (event.type == LocationEventType.geofenceExit) {
          // Repeated exits without a re-entry retain the first departure.
          departure ??= event;
        } else {
          departure = null;
        }
      } else if (event.type != LocationEventType.geofenceExit &&
          departure != null) {
        final departed = departure;
        departure = null;
        final duration = event.recordedAt.difference(departed.recordedAt);
        if (duration < const Duration(minutes: 3) ||
            duration > const Duration(minutes: 180) ||
            LocalDate.fromDateTime(departed.recordedAt) !=
                LocalDate.fromDateTime(event.recordedAt)) {
          continue;
        }
        final fromId = departed.placeId!;
        final toId = place.id;
        trips.add(
          Trip(
            // Length prefixes keep arbitrary place IDs unambiguous.
            id:
                'commute:${fromId.length}:$fromId:${toId.length}:$toId:'
                '${departed.recordedAt.microsecondsSinceEpoch}',
            fromPlaceId: fromId,
            toPlaceId: toId,
            departedAt: departed.recordedAt,
            arrivedAt: event.recordedAt,
          ),
        );
      }
    }
    return trips;
  }

  static int _compareEvents(LocationEvent a, LocationEvent b) {
    final timeOrder = a.recordedAt.compareTo(b.recordedAt);
    if (timeOrder != 0) return timeOrder;
    final idOrder = a.id.compareTo(b.id);
    if (idOrder != 0) return idOrder;
    final typeOrder = a.type.index.compareTo(b.type.index);
    if (typeOrder != 0) return typeOrder;
    return a.placeId!.compareTo(b.placeId!);
  }
}
