import 'package:did_i_attend/src/domain/models/location_event.dart';

abstract interface class LocationEventRepository {
  /// Appends without replacing existing evidence; duplicate IDs are idempotent.
  Future<void> append(LocationEvent event);

  /// Returns events in [from, until), ordered by recordedAt, then ID.
  ///
  /// A null from includes all preceding history to reconstruct an enter with
  /// no subsequent exit. Bounds represent instants and are normalized to UTC.
  /// A place filter retains all position samples, which may have no placeId.
  Future<List<LocationEvent>> query({
    required DateTime until,
    DateTime? from,
    String? placeId,
  });
}
