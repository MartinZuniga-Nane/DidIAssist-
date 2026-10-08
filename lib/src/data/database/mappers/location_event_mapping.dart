import 'package:did_i_attend/src/core/geo_point.dart';
import 'package:did_i_attend/src/data/database/app_database.dart';
import 'package:did_i_attend/src/data/database/mappers/date_mapping.dart';
import 'package:did_i_attend/src/domain/models/location_event.dart';
import 'package:did_i_attend/src/domain/models/location_event_type.dart';
import 'package:drift/drift.dart';

LocationEvent locationEventFromRow(LocationEventRow row) {
  if ((row.latitude == null) != (row.longitude == null)) {
    throw const FormatException('Stored positions require both coordinates.');
  }
  return LocationEvent(
    id: row.id,
    type: LocationEventType.values.byName(row.type),
    placeId: row.placeId,
    position: row.latitude == null
        ? null
        : GeoPoint(latitude: row.latitude!, longitude: row.longitude!),
    accuracyMeters: row.accuracyMeters,
    recordedAt: instantFromMilliseconds(row.recordedAt),
  );
}

LocationEventsCompanion locationEventToCompanion(LocationEvent event) =>
    LocationEventsCompanion.insert(
      id: event.id,
      type: event.type.name,
      placeId: Value(event.placeId),
      latitude: Value(event.position?.latitude),
      longitude: Value(event.position?.longitude),
      accuracyMeters: Value(event.accuracyMeters),
      recordedAt: instantToMilliseconds(event.recordedAt),
    );
