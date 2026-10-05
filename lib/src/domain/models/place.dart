import 'package:did_i_assist/src/core/geo_point.dart';
import 'package:did_i_assist/src/domain/models/model_validation.dart';
import 'package:did_i_assist/src/domain/models/place_kind.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

@immutable
final class Place extends Equatable {
  Place({
    required this.id,
    required this.name,
    required this.kind,
    required this.center,
    this.radiusMeters = 150,
  }) {
    requireNonBlank(id, 'id');
    requireNonBlank(name, 'name');
    if (!radiusMeters.isFinite || radiusMeters < 100 || radiusMeters > 1000) {
      throw ArgumentError.value(
        radiusMeters,
        'radiusMeters',
        'Must be in [100, 1000].',
      );
    }
  }

  final String id;
  final String name;
  final PlaceKind kind;
  final GeoPoint center;
  final double radiusMeters;

  Place copyWith({
    String? id,
    String? name,
    PlaceKind? kind,
    GeoPoint? center,
    double? radiusMeters,
  }) => Place(
    id: id ?? this.id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    center: center ?? this.center,
    radiusMeters: radiusMeters ?? this.radiusMeters,
  );

  @override
  List<Object> get props => [id, name, kind, center, radiusMeters];
}
