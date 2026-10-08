import 'package:did_i_attend/src/domain/models/trip.dart';

abstract interface class TripRepository {
  /// Adds a trip; duplicate IDs are idempotent.
  Future<void> add(Trip trip);

  /// Returns trips for the directed pair, newest arrivedAt first, then ID.
  ///
  /// A null limit includes all history so commute validation can precede
  /// selection of the last ten valid trips.
  Future<List<Trip>> getRecent({
    required String fromPlaceId,
    required String toPlaceId,
    int? limit,
  });
}
