import 'package:did_i_assist/src/core/geo.dart';
import 'package:did_i_assist/src/core/geo_point.dart';
import 'package:did_i_assist/src/domain/models/place.dart';
import 'package:did_i_assist/src/domain/services/departure_advisor.dart';
import 'package:did_i_assist/src/domain/services/eta_estimator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  const advisor = DepartureAdvisor();
  final classOccurrence = occurrence();
  final eta = EtaEstimate(
    duration: const Duration(minutes: 20),
    source: EtaSource.learned,
    sampleSize: 5,
  );
  DepartureAdvice? advise({
    required DateTime now,
    GeoPoint? origin,
    Place? home,
    int buffer = 5,
    EtaEstimate? estimate,
  }) => advisor.advise(
    occurrence: classOccurrence,
    place: classOccurrence.place,
    eta: estimate ?? eta,
    bufferMinutes: buffer,
    now: now,
    origin: origin,
    home: home,
  );

  final boundaries = {
    DateTime(2026, 10, 5, 8, 34, 59, 999, 999): DepartureStatus.onTime,
    DateTime(2026, 10, 5, 8, 35): DepartureStatus.leaveNow,
    DateTime(2026, 10, 5, 8, 40): DepartureStatus.leaveNow,
    DateTime(2026, 10, 5, 8, 40, 0, 0, 1): DepartureStatus.late,
    DateTime(2026, 10, 5, 9): DepartureStatus.late,
  };
  for (final entry in boundaries.entries) {
    test('status ${entry.value.name} at ${entry.key}', () {
      final advice = advise(now: entry.key, origin: eiffelTower())!;
      expect(advice.status, entry.value);
      expect(advice.expectedArrival, entry.key.add(eta.duration));
      expect(advice.leaveBy, DateTime(2026, 10, 5, 8, 35));
      expect(advice.eta, eta);
      expect(advice.originKind, OriginKind.currentPosition);
      if (entry.value != DepartureStatus.late) {
        expect(advice.lateBy, Duration.zero);
      }
    });
  }

  test('lateness rounds up including a single microsecond', () {
    final cases = {
      DateTime(2026, 10, 5, 8, 40, 0, 0, 1): 1,
      DateTime(2026, 10, 5, 8, 41): 1,
      DateTime(2026, 10, 5, 8, 41, 0, 0, 1): 2,
      DateTime(2026, 10, 5, 9): 20,
    };
    for (final entry in cases.entries) {
      final advice = advise(now: entry.key, origin: eiffelTower())!;
      expect(advice.status, DepartureStatus.late);
      expect(advice.lateBy, Duration(minutes: entry.value));
    }
  });

  test('already there overrides ETA and lateness, even after class starts', () {
    final now = DateTime(2026, 10, 5, 9, 30);
    final advice = advise(now: now, origin: louvre())!;
    expect(advice.status, DepartureStatus.alreadyThere);
    expect(advice.eta.duration, Duration.zero);
    expect(advice.eta.sampleSize, 5);
    expect(advice.expectedArrival, now);
    expect(advice.leaveBy, DateTime(2026, 10, 5, 8, 55));
    expect(advice.lateBy, Duration.zero);
  });

  test('campus boundary is inclusive', () {
    final boundary = louvre().copyWith(latitude: 48.8616);
    final place = campusPlace().copyWith(
      radiusMeters: haversineDistanceMeters(louvre(), boundary),
    );
    final advice = advisor.advise(
      occurrence: occurrence(place: place),
      place: place,
      eta: eta,
      bufferMinutes: 0,
      now: DateTime(2026, 10, 5, 8),
      origin: boundary,
    )!;
    expect(advice.status, DepartureStatus.alreadyThere);
  });

  test('zero buffer permits leaving now and arriving exactly at start', () {
    final advice = advise(
      now: DateTime(2026, 10, 5, 8, 40),
      origin: eiffelTower(),
      buffer: 0,
    )!;
    expect(advice.status, DepartureStatus.leaveNow);
    expect(advice.expectedArrival, classOccurrence.start);
    expect(advice.leaveBy, DateTime(2026, 10, 5, 8, 40));
  });

  test('exact start and zero ETA outside campus is leaveNow', () {
    final advice = advise(
      now: classOccurrence.start,
      origin: eiffelTower(),
      buffer: 0,
      estimate: EtaEstimate(
        duration: Duration.zero,
        source: EtaSource.heuristic,
        sampleSize: 0,
      ),
    )!;
    expect(advice.status, DepartureStatus.leaveNow);
    expect(advice.lateBy, Duration.zero);
  });

  test('null current position falls back to home center', () {
    final advice = advise(now: DateTime(2026, 10, 5, 8), home: homePlace())!;
    expect(advice.originKind, OriginKind.home);
    expect(advice.status, DepartureStatus.onTime);
    expect(advice.expectedArrival, DateTime(2026, 10, 5, 8, 20));
  });

  test('current position takes precedence over a home inside campus', () {
    final advice = advise(
      now: DateTime(2026, 10, 5, 8),
      origin: eiffelTower(),
      home: homePlace().copyWith(center: louvre()),
    )!;
    expect(advice.originKind, OriginKind.currentPosition);
    expect(advice.status, DepartureStatus.onTime);
    final fallback = advise(
      now: DateTime(2026, 10, 5, 8),
      home: homePlace().copyWith(center: louvre()),
    )!;
    expect(fallback.status, DepartureStatus.alreadyThere);
    expect(fallback.originKind, OriginKind.home);
  });

  test('no position and no home yields null', () {
    expect(advise(now: DateTime(2026, 10, 5, 8)), isNull);
  });

  test('UTC now and local class times compare as instants', () {
    final now = DateTime(2026, 10, 5, 8, 35);
    final local = advise(now: now, origin: eiffelTower())!;
    final utc = advise(now: now.toUtc(), origin: eiffelTower())!;
    expect(utc.status, local.status);
    expect(utc.expectedArrival.isAtSameMomentAs(local.expectedArrival), isTrue);
    expect(utc.leaveBy, local.leaveBy);
  });

  test('rejects negative buffers and mismatched destination places', () {
    expect(
      () => advise(now: DateTime(2026, 10, 5, 8), buffer: -1),
      throwsArgumentError,
    );
    expect(
      () => advisor.advise(
        occurrence: classOccurrence,
        place: campusPlace(id: 'other-campus'),
        eta: eta,
        bufferMinutes: 5,
        now: DateTime(2026, 10, 5, 8),
      ),
      throwsArgumentError,
    );
  });

  test('advice has value equality across every output field', () {
    final advice = advise(
      now: DateTime(2026, 10, 5, 8),
      origin: eiffelTower(),
    )!;
    final equal = advise(now: DateTime(2026, 10, 5, 8), origin: eiffelTower())!;
    expect(advice, equal);
    expect(advice.hashCode, equal.hashCode);
    DepartureAdvice variant({
      DepartureStatus? status,
      EtaEstimate? estimate,
      DateTime? expectedArrival,
      DateTime? leaveBy,
      Duration? lateBy,
      OriginKind? originKind,
    }) => DepartureAdvice(
      status: status ?? advice.status,
      eta: estimate ?? advice.eta,
      expectedArrival: expectedArrival ?? advice.expectedArrival,
      leaveBy: leaveBy ?? advice.leaveBy,
      lateBy: lateBy ?? advice.lateBy,
      originKind: originKind ?? advice.originKind,
    );
    for (final different in [
      variant(status: DepartureStatus.leaveNow),
      variant(
        estimate: EtaEstimate(
          duration: Duration.zero,
          source: EtaSource.heuristic,
          sampleSize: 0,
        ),
      ),
      variant(
        expectedArrival: advice.expectedArrival.add(const Duration(seconds: 1)),
      ),
      variant(leaveBy: advice.leaveBy.add(const Duration(seconds: 1))),
      variant(lateBy: const Duration(minutes: 1)),
      variant(originKind: OriginKind.home),
    ]) {
      expect(advice, isNot(different));
    }
    expect(
      () => variant(lateBy: const Duration(microseconds: -1)),
      throwsArgumentError,
    );
  });
}
