import 'package:did_i_attend/src/core/geo_point.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

@immutable
final class PositionFix extends Equatable {
  PositionFix({
    required this.position,
    required DateTime timestamp,
    this.accuracyMeters,
  }) : timestamp = timestamp.toUtc() {
    if (accuracyMeters != null &&
        (!accuracyMeters!.isFinite || accuracyMeters! < 0)) {
      throw ArgumentError.value(
        accuracyMeters,
        'accuracyMeters',
        'Must be finite and nonnegative.',
      );
    }
  }

  final GeoPoint position;
  final double? accuracyMeters;
  final DateTime timestamp;

  PositionFix copyWith({
    GeoPoint? position,
    DateTime? timestamp,
    double? Function()? accuracyMeters,
  }) => PositionFix(
    position: position ?? this.position,
    timestamp: timestamp ?? this.timestamp,
    accuracyMeters: accuracyMeters == null
        ? this.accuracyMeters
        : accuracyMeters(),
  );

  @override
  List<Object?> get props => [position, accuracyMeters, timestamp];
}
