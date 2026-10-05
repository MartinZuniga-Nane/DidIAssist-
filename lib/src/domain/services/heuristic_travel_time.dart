import 'package:did_i_assist/src/core/geo.dart';
import 'package:did_i_assist/src/core/geo_point.dart';
import 'package:did_i_assist/src/domain/models/model_validation.dart';
import 'package:did_i_assist/src/domain/models/travel_mode.dart';

final class HeuristicTravelTime {
  HeuristicTravelTime({
    this.detourFactor = 1.3,
    Map<TravelMode, double> speedsKmh = const {},
    Map<TravelMode, Duration> overheads = const {},
  }) : speedsKmh = Map.unmodifiable({..._defaultSpeeds, ...speedsKmh}),
       overheads = Map.unmodifiable({..._defaultOverheads, ...overheads}) {
    requirePositiveFinite(detourFactor, 'detourFactor');
    for (final speed in this.speedsKmh.values) {
      requirePositiveFinite(speed, 'speedsKmh');
    }
    for (final overhead in this.overheads.values) {
      requireNonNegative(overhead.inMicroseconds, 'overheads');
    }
  }

  static const Map<TravelMode, double> _defaultSpeeds = {
    TravelMode.walking: 4.8,
    TravelMode.cycling: 15.0,
    TravelMode.driving: 30.0,
    TravelMode.transit: 18.0,
  };
  static const Map<TravelMode, Duration> _defaultOverheads = {
    TravelMode.walking: Duration.zero,
    TravelMode.cycling: Duration.zero,
    TravelMode.driving: Duration(minutes: 3),
    TravelMode.transit: Duration(minutes: 8),
  };

  final double detourFactor;
  final Map<TravelMode, double> speedsKmh;
  final Map<TravelMode, Duration> overheads;

  Duration estimate({
    required GeoPoint origin,
    required GeoPoint destination,
    required TravelMode mode,
  }) {
    final distanceMeters = haversineDistanceMeters(origin, destination);
    if (distanceMeters == 0) return Duration.zero;
    final travelMinutes =
        distanceMeters / 1000 * detourFactor / speedsKmh[mode]! * 60;
    final overheadMinutes =
        overheads[mode]!.inMicroseconds / Duration.microsecondsPerMinute;
    return Duration(minutes: (travelMinutes + overheadMinutes).ceil());
  }
}
