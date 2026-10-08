import 'package:did_i_attend/src/domain/location/position_fix.dart';
import 'package:did_i_attend/src/domain/models/location_event_type.dart';
import 'package:did_i_attend/src/domain/models/model_validation.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

@immutable
final class GeofenceTransition extends Equatable {
  GeofenceTransition({
    required Iterable<String> placeIds,
    required this.type,
    required DateTime receivedAt,
    this.fix,
  }) : placeIds = List.unmodifiable(placeIds),
       receivedAt = receivedAt.toUtc() {
    if (type == LocationEventType.positionSample) {
      throw ArgumentError('A geofence transition cannot be a position sample.');
    }
    for (final placeId in this.placeIds) {
      requireNonBlank(placeId, 'placeIds');
    }
  }

  final List<String> placeIds;
  final LocationEventType type;
  final PositionFix? fix;
  final DateTime receivedAt;

  @override
  List<Object?> get props => [placeIds, type, fix, receivedAt];
}
