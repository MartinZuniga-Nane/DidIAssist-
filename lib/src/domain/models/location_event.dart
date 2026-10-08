import 'package:did_i_attend/src/core/geo_point.dart';
import 'package:did_i_attend/src/domain/models/location_event_type.dart';
import 'package:did_i_attend/src/domain/models/model_validation.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

@immutable
final class LocationEvent extends Equatable {
  LocationEvent({
    required this.id,
    required this.type,
    required DateTime recordedAt,
    this.placeId,
    this.position,
    this.accuracyMeters,
  }) : recordedAt = recordedAt.toUtc() {
    requireNonBlank(id, 'id');
    if (placeId != null) requireNonBlank(placeId!, 'placeId');
    if (type != LocationEventType.positionSample && placeId == null) {
      throw ArgumentError('Geofence events require a placeId.');
    }
    if (type == LocationEventType.positionSample && position == null) {
      throw ArgumentError('Position samples require a position.');
    }
    if (accuracyMeters != null &&
        (!accuracyMeters!.isFinite || accuracyMeters! < 0)) {
      throw ArgumentError.value(
        accuracyMeters,
        'accuracyMeters',
        'Must be finite and nonnegative.',
      );
    }
  }

  final String id;
  final LocationEventType type;
  final String? placeId;
  final GeoPoint? position;
  final double? accuracyMeters;
  final DateTime recordedAt;

  LocationEvent copyWith({
    String? id,
    LocationEventType? type,
    String? Function()? placeId,
    GeoPoint? Function()? position,
    double? Function()? accuracyMeters,
    DateTime? recordedAt,
  }) => LocationEvent(
    id: id ?? this.id,
    type: type ?? this.type,
    placeId: placeId == null ? this.placeId : placeId(),
    position: position == null ? this.position : position(),
    accuracyMeters: accuracyMeters == null
        ? this.accuracyMeters
        : accuracyMeters(),
    recordedAt: recordedAt ?? this.recordedAt,
  );

  @override
  List<Object?> get props => [
    id,
    type,
    placeId,
    position,
    accuracyMeters,
    recordedAt,
  ];
}
