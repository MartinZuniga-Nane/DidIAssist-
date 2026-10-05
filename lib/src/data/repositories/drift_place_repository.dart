import 'package:did_i_assist/src/data/database/app_database.dart';
import 'package:did_i_assist/src/data/database/mappers/place_mapping.dart';
import 'package:did_i_assist/src/data/database/tables.dart';
import 'package:did_i_assist/src/data/repositories/place_in_use_exception.dart';
import 'package:did_i_assist/src/domain/models/place.dart';
import 'package:did_i_assist/src/domain/repositories/place_repository.dart';
import 'package:drift/drift.dart';

final class DriftPlaceRepository implements PlaceRepository {
  DriftPlaceRepository(this._database);

  final AppDatabase _database;

  @override
  Future<Place?> getById(String id) async {
    final row = await (_database.select(
      _database.places,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    return row == null ? null : placeFromRow(row);
  }

  SimpleSelectStatement<Places, PlaceRow> _all() =>
      _database.select(_database.places)..orderBy([
        (table) => OrderingTerm.asc(table.name),
        (table) => OrderingTerm.asc(table.id),
      ]);

  @override
  Future<List<Place>> getAll() => _all().map(placeFromRow).get();

  @override
  Stream<List<Place>> watchAll() => _all().map(placeFromRow).watch();

  @override
  Future<void> save(Place place) async {
    await _database
        .into(_database.places)
        .insertOnConflictUpdate(
          placeToCompanion(place),
        );
  }

  @override
  Future<void> delete(String id) => _database.transaction(() async {
    final references =
        await (_database.select(_database.scheduleSlots)
              ..where((table) => table.placeId.equals(id))
              ..limit(1))
            .get();
    if (references.isNotEmpty) throw PlaceInUseException(id);
    await (_database.delete(
      _database.places,
    )..where((table) => table.id.equals(id))).go();
  });
}
