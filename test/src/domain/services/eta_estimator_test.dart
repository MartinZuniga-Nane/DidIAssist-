import 'package:did_i_assist/src/core/geo.dart';
import 'package:did_i_assist/src/core/geo_point.dart';
import 'package:did_i_assist/src/domain/models/models.dart';
import 'package:did_i_assist/src/domain/services/commute_learner.dart';
import 'package:did_i_assist/src/domain/services/eta_estimator.dart';
import 'package:did_i_assist/src/domain/services/heuristic_travel_time.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  final estimator = EtaEstimator();
  EtaEstimate estimate({
    int n = 0,
    Duration median = const Duration(minutes: 22),
    GeoPoint? origin,
    Place? home,
    Place? destination,
  }) => estimator.estimate(
    origin: origin ?? eiffelTower(),
    destination: destination ?? campusPlace(),
    mode: TravelMode.walking,
    home: home ?? homePlace(),
    learned: CommuteStats(medianDuration: median, sampleSize: n),
  );

  const weights = {
    0: (52, EtaSource.heuristic),
    2: (52, EtaSource.heuristic),
    3: (42, EtaSource.blended),
    4: (32, EtaSource.blended),
    5: (22, EtaSource.learned),
    10: (22, EtaSource.learned),
  };
  for (final entry in weights.entries) {
    test('home weight at n = ${entry.key}', () {
      expect(
        estimate(n: entry.key),
        EtaEstimate(
          duration: Duration(minutes: entry.value.$1),
          source: entry.value.$2,
          sampleSize: entry.key,
        ),
      );
    });
  }

  test('blends round up while a learned estimate preserves seconds', () {
    const median = Duration(minutes: 22, seconds: 30);
    expect(
      estimate(n: 3, median: median).duration,
      const Duration(minutes: 43),
    );
    expect(
      estimate(n: 4, median: median).duration,
      const Duration(minutes: 33),
    );
    expect(estimate(n: 5, median: median).duration, median);
  });

  test('a position exactly on the home geofence uses learned data', () {
    final boundary = eiffelTower().copyWith(latitude: 48.8594);
    final home = homePlace().copyWith(
      radiusMeters: haversineDistanceMeters(eiffelTower(), boundary),
    );
    expect(
      estimate(n: 5, origin: boundary, home: home).source,
      EtaSource.learned,
    );
  });

  test('inside destination overrides all learned samples and sources', () {
    for (final n in [0, 2, 3, 4, 5, 10]) {
      final eta = estimate(n: n, origin: louvre());
      expect(eta.duration, Duration.zero);
      expect(eta.source, EtaSource.heuristic);
      expect(eta.sampleSize, n);
    }
  });

  test(
    'destination radius is inclusive and immediately outside needs travel',
    () {
      final boundary = louvre().copyWith(latitude: 48.8616);
      final destination = campusPlace().copyWith(
        radiusMeters: haversineDistanceMeters(louvre(), boundary),
      );
      expect(
        estimate(origin: boundary, destination: destination).duration,
        Duration.zero,
      );
      expect(
        estimate(
          origin: boundary.copyWith(latitude: 48.861601),
          destination: destination,
        ).duration,
        greaterThan(Duration.zero),
      );
    },
  );

  test('other origins stay heuristic with fewer than three samples', () {
    for (final n in [0, 1, 2]) {
      final eta = estimate(n: n, origin: arcDeTriomphe());
      expect(eta.source, EtaSource.heuristic);
      expect(eta.duration, const Duration(minutes: 56));
      expect(eta.sampleSize, n);
    }
  });

  test('other origins calibrate at three samples using the home baseline', () {
    final eta = estimate(
      n: 3,
      origin: arcDeTriomphe(),
      median: const Duration(minutes: 39),
    );
    expect(eta.duration, const Duration(minutes: 42));
    expect(eta.source, EtaSource.blended);
    expect(eta.sampleSize, 3);
  });

  test('calibration clamps to one half and three times the heuristic', () {
    final lower = estimate(
      n: 10,
      origin: arcDeTriomphe(),
      median: const Duration(minutes: 3),
    );
    final upper = estimate(
      n: 10,
      origin: arcDeTriomphe(),
      median: const Duration(minutes: 180),
    );
    expect(lower.duration, const Duration(minutes: 28));
    expect(upper.duration, const Duration(minutes: 168));
    expect(lower.source, EtaSource.blended);
    expect(upper.source, EtaSource.blended);
  });

  test('calibrated fractions round up to whole minutes', () {
    expect(
      estimate(n: 3, origin: arcDeTriomphe()).duration,
      const Duration(minutes: 28),
    );
    expect(
      estimate(
        n: 3,
        origin: arcDeTriomphe(),
        median: const Duration(minutes: 30),
      ).duration,
      const Duration(minutes: 33),
    );
    expect(
      estimate(
        n: 3,
        origin: arcDeTriomphe(),
        median: const Duration(minutes: 120),
      ).duration,
      const Duration(minutes: 130),
    );
  });

  test('no home or no learned data uses the selected mode heuristic', () {
    final learned = CommuteStats(
      medianDuration: const Duration(minutes: 10),
      sampleSize: 10,
    );
    expect(
      estimator.estimate(
        origin: eiffelTower(),
        destination: campusPlace(),
        mode: TravelMode.transit,
        learned: learned,
      ),
      EtaEstimate(
        duration: const Duration(minutes: 22),
        source: EtaSource.heuristic,
        sampleSize: 10,
      ),
    );
    expect(
      estimator.estimate(
        origin: eiffelTower(),
        destination: campusPlace(),
        mode: TravelMode.cycling,
        home: homePlace(),
      ),
      EtaEstimate(
        duration: const Duration(minutes: 17),
        source: EtaSource.heuristic,
        sampleSize: 0,
      ),
    );
  });

  test(
    'coincident home and destination centers cannot calibrate other origins',
    () {
      final eta = estimate(
        n: 10,
        origin: arcDeTriomphe(),
        home: homePlace().copyWith(center: louvre()),
      );
      expect(eta.duration, const Duration(minutes: 56));
      expect(eta.source, EtaSource.heuristic);
    },
  );

  test('accepts a configured heuristic', () {
    final custom =
        EtaEstimator(
          heuristicTravelTime: HeuristicTravelTime(detourFactor: 2.6),
        ).estimate(
          origin: eiffelTower(),
          destination: campusPlace(),
          mode: TravelMode.walking,
        );
    expect(custom.duration, const Duration(minutes: 103));
  });

  test('estimate has value equality and rejects negative values', () {
    final eta = estimate(n: 3);
    expect(eta, estimate(n: 3));
    expect(eta.hashCode, estimate(n: 3).hashCode);
    for (final variant in [
      EtaEstimate(duration: Duration.zero, source: eta.source, sampleSize: 3),
      EtaEstimate(
        duration: eta.duration,
        source: EtaSource.learned,
        sampleSize: 3,
      ),
      EtaEstimate(duration: eta.duration, source: eta.source, sampleSize: 4),
    ]) {
      expect(eta, isNot(variant));
    }
    expect(
      () => EtaEstimate(
        duration: const Duration(microseconds: -1),
        source: EtaSource.heuristic,
        sampleSize: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => EtaEstimate(
        duration: Duration.zero,
        source: EtaSource.heuristic,
        sampleSize: -1,
      ),
      throwsArgumentError,
    );
  });
}
