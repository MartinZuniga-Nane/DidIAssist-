import 'package:did_i_attend/src/domain/models/model_validation.dart';
import 'package:did_i_attend/src/domain/models/travel_mode.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

@immutable
final class Trip extends Equatable {
  Trip({
    required this.id,
    required this.fromPlaceId,
    required this.toPlaceId,
    required DateTime departedAt,
    required DateTime arrivedAt,
    this.mode,
  }) : departedAt = departedAt.toUtc(),
       arrivedAt = arrivedAt.toUtc() {
    requireNonBlank(id, 'id');
    requireNonBlank(fromPlaceId, 'fromPlaceId');
    requireNonBlank(toPlaceId, 'toPlaceId');
    if (fromPlaceId == toPlaceId) {
      throw ArgumentError('Trip endpoints must be different places.');
    }
    if (!this.arrivedAt.isAfter(this.departedAt)) {
      throw ArgumentError('arrivedAt must follow departedAt.');
    }
  }

  final String id;
  final String fromPlaceId;
  final String toPlaceId;
  final DateTime departedAt;
  final DateTime arrivedAt;
  final TravelMode? mode;

  Duration get duration => arrivedAt.difference(departedAt);

  Trip copyWith({
    String? id,
    String? fromPlaceId,
    String? toPlaceId,
    DateTime? departedAt,
    DateTime? arrivedAt,
    TravelMode? Function()? mode,
  }) => Trip(
    id: id ?? this.id,
    fromPlaceId: fromPlaceId ?? this.fromPlaceId,
    toPlaceId: toPlaceId ?? this.toPlaceId,
    departedAt: departedAt ?? this.departedAt,
    arrivedAt: arrivedAt ?? this.arrivedAt,
    mode: mode == null ? this.mode : mode(),
  );

  @override
  List<Object?> get props => [
    id,
    fromPlaceId,
    toPlaceId,
    departedAt,
    arrivedAt,
    mode,
  ];
}
