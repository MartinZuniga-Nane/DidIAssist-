import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

@immutable
final class GeoPoint extends Equatable {
  GeoPoint({required this.latitude, required this.longitude}) {
    if (!latitude.isFinite || latitude < -90 || latitude > 90) {
      throw ArgumentError.value(latitude, 'latitude', 'Must be in [-90, 90].');
    }
    if (!longitude.isFinite || longitude < -180 || longitude > 180) {
      throw ArgumentError.value(
        longitude,
        'longitude',
        'Must be in [-180, 180].',
      );
    }
  }

  final double latitude;
  final double longitude;

  GeoPoint copyWith({double? latitude, double? longitude}) => GeoPoint(
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
  );

  @override
  List<Object> get props => [latitude, longitude];
}
