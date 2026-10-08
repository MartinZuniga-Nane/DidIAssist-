import 'package:clock/clock.dart';
import 'package:did_i_attend/src/domain/models/model_validation.dart';
import 'package:did_i_attend/src/domain/models/trip.dart';
import 'package:did_i_attend/src/domain/repositories/location_event_repository.dart';
import 'package:did_i_attend/src/domain/repositories/place_repository.dart';
import 'package:did_i_attend/src/domain/repositories/trip_repository.dart';
import 'package:did_i_attend/src/domain/services/trip_detector.dart';

final class TripRecorder {
  TripRecorder({
    required LocationEventRepository locationEventRepository,
    required PlaceRepository placeRepository,
    required TripRepository tripRepository,
    Clock? timeSource,
    TripDetector detector = const TripDetector(),
  }) : _events = locationEventRepository,
       _places = placeRepository,
       _trips = tripRepository,
       _clock = timeSource ?? clock,
       _detector = detector;

  final LocationEventRepository _events;
  final PlaceRepository _places;
  final TripRepository _trips;
  final Clock _clock;
  final TripDetector _detector;

  Future<List<Trip>> recordRecent({
    Duration lookback = const Duration(days: 7),
  }) async {
    requireNonNegative(lookback.inMicroseconds, 'lookback');
    final now = _clock.now().toUtc();
    final places = await _places.getAll();
    final events = await _events.query(
      from: now.subtract(lookback),
      until: now,
    );
    final detected = _detector.detect(events: events, places: places);
    final knownIds = <(String, String), Set<String>>{};
    final recorded = <Trip>[];
    for (final trip in detected) {
      final pair = (trip.fromPlaceId, trip.toPlaceId);
      if (!knownIds.containsKey(pair)) {
        final existing = await _trips.getRecent(
          fromPlaceId: trip.fromPlaceId,
          toPlaceId: trip.toPlaceId,
        );
        knownIds[pair] = existing.map((trip) => trip.id).toSet();
      }
      if (knownIds[pair]!.contains(trip.id)) continue;
      await _trips.add(trip);
      knownIds[pair]!.add(trip.id);
      recorded.add(trip);
    }
    return recorded;
  }
}
