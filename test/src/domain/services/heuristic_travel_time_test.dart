import 'package:did_i_attend/src/core/geo.dart';
import 'package:did_i_attend/src/domain/models/travel_mode.dart';
import 'package:did_i_attend/src/domain/services/heuristic_travel_time.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  final heuristic = HeuristicTravelTime();
  const expectedMinutes = {
    TravelMode.walking: 52,
    TravelMode.cycling: 17,
    TravelMode.driving: 12,
    TravelMode.transit: 22,
  };
  for (final entry in expectedMinutes.entries) {
    test('Eiffel Tower to Louvre by ${entry.key.name}', () {
      expect(
        heuristic.estimate(
          origin: eiffelTower(),
          destination: louvre(),
          mode: entry.key,
        ),
        Duration(minutes: entry.value),
      );
    });

    test('zero distance has no overhead by ${entry.key.name}', () {
      expect(
        heuristic.estimate(
          origin: eiffelTower(),
          destination: eiffelTower(),
          mode: entry.key,
        ),
        Duration.zero,
      );
    });
  }

  test('driving and transit add their default overheads', () {
    for (final mode in [TravelMode.driving, TravelMode.transit]) {
      final withoutOverhead = HeuristicTravelTime(
        overheads: {mode: Duration.zero},
      ).estimate(origin: eiffelTower(), destination: louvre(), mode: mode);
      final withOverhead = heuristic.estimate(
        origin: eiffelTower(),
        destination: louvre(),
        mode: mode,
      );
      expect(
        withOverhead - withoutOverhead,
        Duration(minutes: mode == TravelMode.driving ? 3 : 8),
      );
    }
  });

  test('injects factor, speed and fractional overhead and rounds up', () {
    final distanceKm = haversineDistanceMeters(eiffelTower(), louvre()) / 1000;
    final custom = HeuristicTravelTime(
      detourFactor: 1,
      speedsKmh: {TravelMode.walking: distanceKm * 60},
      overheads: {TravelMode.walking: const Duration(microseconds: 1)},
    );
    expect(
      custom.estimate(
        origin: eiffelTower(),
        destination: louvre(),
        mode: TravelMode.walking,
      ),
      const Duration(minutes: 2),
    );
  });

  test('exact whole minutes are not rounded to the next minute', () {
    final distanceKm = haversineDistanceMeters(eiffelTower(), louvre()) / 1000;
    expect(
      HeuristicTravelTime(
        detourFactor: 1,
        speedsKmh: {TravelMode.cycling: distanceKm * 60},
      ).estimate(
        origin: eiffelTower(),
        destination: louvre(),
        mode: TravelMode.cycling,
      ),
      const Duration(minutes: 1),
    );
  });

  test('copies injected maps and keeps unspecified mode defaults', () {
    final speeds = {TravelMode.walking: 9.6};
    final overheads = {TravelMode.walking: const Duration(minutes: 1)};
    final custom = HeuristicTravelTime(speedsKmh: speeds, overheads: overheads);
    speeds[TravelMode.walking] = 1;
    overheads.clear();
    expect(custom.speedsKmh[TravelMode.walking], 9.6);
    expect(custom.overheads[TravelMode.walking], const Duration(minutes: 1));
    expect(custom.speedsKmh[TravelMode.transit], 18);
    expect(custom.speedsKmh.clear, throwsUnsupportedError);
    expect(custom.overheads.clear, throwsUnsupportedError);
  });

  test('rejects invalid factors, speeds and negative overheads', () {
    for (final invalid in [0.0, -1.0, double.nan, double.infinity]) {
      expect(
        () => HeuristicTravelTime(detourFactor: invalid),
        throwsArgumentError,
      );
      expect(
        () => HeuristicTravelTime(speedsKmh: {TravelMode.walking: invalid}),
        throwsArgumentError,
      );
    }
    expect(
      () => HeuristicTravelTime(
        overheads: {TravelMode.transit: const Duration(microseconds: -1)},
      ),
      throwsArgumentError,
    );
  });
}
