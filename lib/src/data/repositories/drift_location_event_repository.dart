import 'package:did_i_assist/src/data/database/app_database.dart';
import 'package:did_i_assist/src/data/database/mappers/date_mapping.dart';
import 'package:did_i_assist/src/data/database/mappers/location_event_mapping.dart';
import 'package:did_i_assist/src/domain/models/location_event.dart';
import 'package:did_i_assist/src/domain/models/location_event_type.dart';
import 'package:did_i_assist/src/domain/repositories/location_event_repository.dart';
import 'package:drift/drift.dart';

final class DriftLocationEventRepository implements LocationEventRepository {
  DriftLocationEventRepository(this._database);

  final AppDatabase _database;

  @override
  Future<void> append(LocationEvent event) async {
    await _database
        .into(_database.locationEvents)
        .insert(
          locationEventToCompanion(event),
          mode: InsertMode.insertOrIgnore,
        );
  }

  @override
  Future<List<LocationEvent>> query({
    required DateTime until,
    DateTime? from,
    String? placeId,
  }) {
    final query = _database.select(_database.locationEvents)
      ..where(
        (table) => table.recordedAt.isSmallerThanValue(
          instantCeilingMilliseconds(until),
        ),
      );
    if (from != null) {
      query.where(
        (table) => table.recordedAt.isBiggerOrEqualValue(
          instantCeilingMilliseconds(from),
        ),
      );
    }
    if (placeId != null) {
      query.where(
        (table) =>
            table.placeId.equals(placeId) |
            table.type.equals(LocationEventType.positionSample.name),
      );
    }
    return (query..orderBy([
          (table) => OrderingTerm.asc(table.recordedAt),
          (table) => OrderingTerm.asc(table.id),
        ]))
        .map(locationEventFromRow)
        .get();
  }
}
