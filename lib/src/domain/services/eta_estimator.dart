import 'package:did_i_attend/src/core/geo.dart';
import 'package:did_i_attend/src/core/geo_point.dart';
import 'package:did_i_attend/src/domain/models/model_validation.dart';
import 'package:did_i_attend/src/domain/models/place.dart';
import 'package:did_i_attend/src/domain/models/travel_mode.dart';
import 'package:did_i_attend/src/domain/services/commute_learner.dart';
import 'package:did_i_attend/src/domain/services/heuristic_travel_time.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

enum EtaSource { heuristic, learned, blended }

@immutable
final class EtaEstimate extends Equatable {
  EtaEstimate({
    required this.duration,
    required this.source,
    required this.sampleSize,
  }) {
    requireNonNegative(duration.inMicroseconds, 'duration');
    requireNonNegative(sampleSize, 'sampleSize');
  }

  final Duration duration;
  final EtaSource source;
  final int sampleSize;

  @override
  List<Object> get props => [duration, source, sampleSize];
}

final class EtaEstimator {
  EtaEstimator({HeuristicTravelTime? heuristicTravelTime})
    : _heuristic = heuristicTravelTime ?? HeuristicTravelTime();

  final HeuristicTravelTime _heuristic;

  EtaEstimate estimate({
    required GeoPoint origin,
    required Place destination,
    required TravelMode mode,
    Place? home,
    CommuteStats? learned,
  }) {
    final n = learned?.sampleSize ?? 0;
    EtaEstimate result(Duration duration, EtaSource source) => EtaEstimate(
      duration: duration,
      source: source,
      sampleSize: n,
    );

    if (haversineDistanceMeters(origin, destination.center) <=
        destination.radiusMeters) {
      return result(Duration.zero, EtaSource.heuristic);
    }
    final heuristic = _heuristic.estimate(
      origin: origin,
      destination: destination.center,
      mode: mode,
    );
    if (home == null || learned == null || n < 3) {
      return result(heuristic, EtaSource.heuristic);
    }
    if (haversineDistanceMeters(origin, home.center) <= home.radiusMeters) {
      if (n >= 5) return result(learned.medianDuration, EtaSource.learned);
      // Integer thirds avoid rounding an exact minute up due to floating point.
      final numerator =
          (n - 2) * learned.medianDuration.inMicroseconds +
          (5 - n) * heuristic.inMicroseconds;
      return result(
        _ceilRatio(numerator, 3 * Duration.microsecondsPerMinute),
        EtaSource.blended,
      );
    }
    final homeHeuristic = _heuristic.estimate(
      origin: home.center,
      destination: destination.center,
      mode: mode,
    );
    // Coincident centers cannot supply a calibration ratio.
    if (homeHeuristic == Duration.zero) {
      return result(heuristic, EtaSource.heuristic);
    }
    final median = learned.medianDuration.inMicroseconds;
    final baseline = homeHeuristic.inMicroseconds;
    final (numerator, denominator) = median * 2 < baseline
        ? (1, 2)
        : median > baseline * 3
        ? (3, 1)
        : (median, baseline);
    return result(
      _ceilRatio(
        heuristic.inMinutes * numerator,
        denominator,
      ),
      EtaSource.blended,
    );
  }

  static Duration _ceilRatio(int numerator, int denominator) => Duration(
    minutes: (numerator + denominator - 1) ~/ denominator,
  );
}
