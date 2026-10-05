import 'package:did_i_assist/src/data/database/app_database.dart';
import 'package:did_i_assist/src/data/database/mappers/trip_mapping.dart';
import 'package:did_i_assist/src/domain/models/trip.dart';
import 'package:did_i_assist/src/domain/repositories/trip_repository.dart';
import 'package:drift/drift.dart';

final class DriftTripRepository implements TripRepository {
  DriftTripRepository(this._database);

  final AppDatabase _database;

  @override
  Future<void> add(Trip trip) async {
    await _database
        .into(_database.trips)
        .insert(
          tripToCompanion(trip),
          mode: InsertMode.insertOrIgnore,
        );
  }

  @override
  Future<List<Trip>> getRecent({
    required String fromPlaceId,
    required String toPlaceId,
    int? limit,
  }) {
    if (limit != null && limit < 0) {
      throw RangeError.value(limit, 'limit', 'Must be nonnegative.');
    }
    final query = _database.select(_database.trips)
      ..where(
        (table) =>
            table.fromPlaceId.equals(fromPlaceId) &
            table.toPlaceId.equals(toPlaceId),
      )
      ..orderBy([
        (table) => OrderingTerm.desc(table.arrivedAt),
        (table) => OrderingTerm.asc(table.id),
      ]);
    if (limit != null) query.limit(limit);
    return query.map(tripFromRow).get();
  }
}
