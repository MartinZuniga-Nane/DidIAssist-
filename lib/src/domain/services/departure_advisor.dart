import 'package:did_i_assist/src/core/geo.dart';
import 'package:did_i_assist/src/core/geo_point.dart';
import 'package:did_i_assist/src/domain/models/class_occurrence.dart';
import 'package:did_i_assist/src/domain/models/model_validation.dart';
import 'package:did_i_assist/src/domain/models/place.dart';
import 'package:did_i_assist/src/domain/services/eta_estimator.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

enum DepartureStatus { alreadyThere, onTime, leaveNow, late }

enum OriginKind { currentPosition, home }

@immutable
final class DepartureAdvice extends Equatable {
  DepartureAdvice({
    required this.status,
    required this.eta,
    required this.expectedArrival,
    required this.leaveBy,
    required this.lateBy,
    required this.originKind,
  }) {
    requireNonNegative(lateBy.inMicroseconds, 'lateBy');
  }

  final DepartureStatus status;
  final EtaEstimate eta;
  final DateTime expectedArrival;
  final DateTime leaveBy;
  final Duration lateBy;
  final OriginKind originKind;

  @override
  List<Object> get props => [
    status,
    eta,
    expectedArrival,
    leaveBy,
    lateBy,
    originKind,
  ];
}

final class DepartureAdvisor {
  const DepartureAdvisor();

  DepartureAdvice? advise({
    required ClassOccurrence occurrence,
    required Place place,
    required EtaEstimate eta,
    required int bufferMinutes,
    required DateTime now,
    GeoPoint? origin,
    Place? home,
  }) {
    requireNonNegative(bufferMinutes, 'bufferMinutes');
    if (place.id != occurrence.place.id) {
      throw ArgumentError('place must match the occurrence destination.');
    }
    final usableOrigin = origin ?? home?.center;
    if (usableOrigin == null) return null;
    final alreadyThere =
        haversineDistanceMeters(usableOrigin, place.center) <=
        place.radiusMeters;
    final effectiveEta = alreadyThere
        ? EtaEstimate(
            duration: Duration.zero,
            source: EtaSource.heuristic,
            sampleSize: eta.sampleSize,
          )
        : eta;
    final expectedArrival = now.add(effectiveEta.duration);
    final leaveBy = occurrence.start
        .subtract(effectiveEta.duration)
        .subtract(Duration(minutes: bufferMinutes));
    final lateness = expectedArrival.difference(occurrence.start);
    final status = alreadyThere
        ? DepartureStatus.alreadyThere
        : lateness > Duration.zero
        ? DepartureStatus.late
        : leaveBy.isAfter(now)
        ? DepartureStatus.onTime
        : DepartureStatus.leaveNow;
    return DepartureAdvice(
      status: status,
      eta: effectiveEta,
      expectedArrival: expectedArrival,
      leaveBy: leaveBy,
      lateBy: status == DepartureStatus.late
          ? Duration(
              minutes:
                  (lateness.inMicroseconds / Duration.microsecondsPerMinute)
                      .ceil(),
            )
          : Duration.zero,
      originKind: origin == null ? OriginKind.home : OriginKind.currentPosition,
    );
  }
}
