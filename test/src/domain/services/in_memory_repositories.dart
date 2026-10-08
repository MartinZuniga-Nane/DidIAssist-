import 'package:did_i_attend/src/domain/models/models.dart';
import 'package:did_i_attend/src/domain/repositories/location_event_repository.dart';
import 'package:did_i_attend/src/domain/repositories/place_repository.dart';
import 'package:did_i_attend/src/domain/repositories/settings_repository.dart';
import 'package:did_i_attend/src/domain/repositories/trip_repository.dart';

final class InMemoryPlaceRepository implements PlaceRepository {
  InMemoryPlaceRepository([Iterable<Place> initial = const []])
    : places = {for (final place in initial) place.id: place};

  final Map<String, Place> places;

  @override
  Future<Place?> getById(String id) async => places[id];

  @override
  Future<List<Place>> getAll() async => places.values.toList();

  @override
  Stream<List<Place>> watchAll() => Stream.value(places.values.toList());

  @override
  Future<void> save(Place place) async => places[place.id] = place;

  @override
  Future<void> delete(String id) async => places.remove(id);
}

final class InMemoryLocationEventRepository implements LocationEventRepository {
  InMemoryLocationEventRepository([Iterable<LocationEvent> initial = const []])
    : events = {for (final event in initial) event.id: event};

  final Map<String, LocationEvent> events;
  DateTime? queriedFrom;
  DateTime? queriedUntil;

  @override
  Future<void> append(LocationEvent event) async {
    events.putIfAbsent(event.id, () => event);
  }

  @override
  Future<List<LocationEvent>> query({
    required DateTime until,
    DateTime? from,
    String? placeId,
  }) async {
    queriedFrom = from;
    queriedUntil = until;
    return events.values
        .where(
          (event) =>
              (from == null || !event.recordedAt.isBefore(from)) &&
              event.recordedAt.isBefore(until) &&
              (placeId == null ||
                  event.placeId == placeId ||
                  event.type == LocationEventType.positionSample),
        )
        .toList()
      ..sort((a, b) {
        final order = a.recordedAt.compareTo(b.recordedAt);
        return order != 0 ? order : a.id.compareTo(b.id);
      });
  }
}

final class InMemoryTripRepository implements TripRepository {
  InMemoryTripRepository([Iterable<Trip> initial = const []])
    : trips = {for (final trip in initial) trip.id: trip};

  final Map<String, Trip> trips;
  final added = <Trip>[];
  final queries = <(String, String, int?)>[];

  @override
  Future<void> add(Trip trip) async {
    added.add(trip);
    trips.putIfAbsent(trip.id, () => trip);
  }

  @override
  Future<List<Trip>> getRecent({
    required String fromPlaceId,
    required String toPlaceId,
    int? limit,
  }) async {
    queries.add((fromPlaceId, toPlaceId, limit));
    final matching =
        trips.values
            .where(
              (trip) =>
                  trip.fromPlaceId == fromPlaceId &&
                  trip.toPlaceId == toPlaceId,
            )
            .toList()
          ..sort((a, b) {
            final order = b.arrivedAt.compareTo(a.arrivedAt);
            return order != 0 ? order : a.id.compareTo(b.id);
          });
    return limit == null ? matching : matching.take(limit).toList();
  }
}

final class InMemorySettingsRepository implements SettingsRepository {
  InMemorySettingsRepository([UserSettings? initial])
    : settings = initial ?? UserSettings();

  UserSettings settings;
  int loadCount = 0;

  @override
  Future<UserSettings> load() async {
    loadCount++;
    return settings;
  }

  @override
  Future<void> save(UserSettings settings) async => this.settings = settings;

  @override
  Stream<UserSettings> watch() => Stream.value(settings);
}
