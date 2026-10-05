import 'package:did_i_assist/src/domain/models/trip.dart';
import 'package:did_i_assist/src/domain/services/commute_learner.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  const learner = CommuteLearner();
  CommuteStats learn(Iterable<Trip> trips) => learner.learn(
    trips: trips,
    fromPlaceId: 'home',
    toPlaceId: 'campus',
  );

  test('no valid trips has zero duration and zero samples', () {
    expect(
      learn([]),
      CommuteStats(medianDuration: Duration.zero, sampleSize: 0),
    );
  });

  test('odd median resists outliers and retains the middle duration', () {
    expect(
      learn([
        commute(id: 'a', duration: const Duration(minutes: 10)),
        commute(id: 'b', duration: const Duration(minutes: 180)),
        commute(id: 'c', duration: const Duration(minutes: 20, seconds: 1)),
      ]),
      CommuteStats(
        medianDuration: const Duration(minutes: 20, seconds: 1),
        sampleSize: 3,
      ),
    );
  });

  test('even median is the mean rounded to the nearest whole second', () {
    final stats = learn([
      commute(id: 'a', duration: const Duration(minutes: 10)),
      commute(id: 'b', duration: const Duration(minutes: 20, seconds: 1)),
    ]);
    expect(stats.medianDuration, const Duration(minutes: 15, seconds: 1));
    expect(stats.sampleSize, 2);
    expect(
      learn([
        commute(id: 'a', duration: const Duration(minutes: 10)),
        commute(
          id: 'b',
          duration: const Duration(minutes: 20, milliseconds: 1),
        ),
      ]).medianDuration,
      const Duration(minutes: 15),
    );
  });

  test('single trip preserves its precision', () {
    const duration = Duration(minutes: 10, microseconds: 1);
    expect(learn([commute(duration: duration)]).medianDuration, duration);
  });

  test('sorts by arrival and uses the last ten valid trips only', () {
    final trips = [
      for (var i = 0; i < 12; i++)
        commute(
          id: 'trip-$i',
          duration: Duration(minutes: i + 10),
          arrivedAt: DateTime(2026, 10, i + 1, 9),
        ),
    ];
    expect(
      learn(trips.reversed),
      CommuteStats(
        medianDuration: const Duration(minutes: 16, seconds: 30),
        sampleSize: 10,
      ),
    );
  });

  test('filters invalid trips before selecting the ten-trip window', () {
    final valid = [
      for (var i = 0; i < 10; i++)
        commute(
          id: 'valid-$i',
          duration: const Duration(minutes: 20),
          arrivedAt: DateTime(2026, 10, i + 1, 9),
        ),
    ];
    final invalid = [
      for (var i = 0; i < 12; i++)
        commute(
          id: 'invalid-$i',
          duration: i.isEven
              ? const Duration(minutes: 3, microseconds: -1)
              : const Duration(minutes: 180, microseconds: 1),
          arrivedAt: DateTime(2026, 10, i + 12, 9),
        ),
    ];
    expect(
      learn([...valid, ...invalid]),
      CommuteStats(medianDuration: const Duration(minutes: 20), sampleSize: 10),
    );
  });

  test(
    'duration endpoints are inclusive and only the directed pair counts',
    () {
      final stats = learn([
        commute(id: 'min', duration: const Duration(minutes: 3)),
        commute(id: 'max', duration: const Duration(minutes: 180)),
        commute(
          id: 'reverse',
          fromPlaceId: 'campus',
          toPlaceId: 'home',
          duration: const Duration(minutes: 10),
        ),
        commute(
          id: 'other-origin',
          fromPlaceId: 'other-home',
          duration: const Duration(minutes: 10),
        ),
        commute(
          id: 'other-destination',
          toPlaceId: 'other-campus',
          duration: const Duration(minutes: 10),
        ),
      ]);
      expect(stats.sampleSize, 2);
      expect(stats.medianDuration, const Duration(minutes: 91, seconds: 30));
    },
  );

  test('arrival ties use ID ordering independently of input order', () {
    final trips = [
      for (var i = 0; i < 10; i++)
        commute(id: 'a-$i', duration: const Duration(minutes: 10)),
      commute(id: 'z', duration: const Duration(minutes: 180)),
    ];
    expect(learn(trips), learn(trips.reversed));
    expect(learn(trips).medianDuration, const Duration(minutes: 10));
    expect(learn(trips).sampleSize, 10);
  });

  test('stats have value equality and reject negative values', () {
    final stats = CommuteStats(
      medianDuration: const Duration(minutes: 10),
      sampleSize: 3,
    );
    final equal = CommuteStats(
      medianDuration: const Duration(minutes: 10),
      sampleSize: 3,
    );
    expect(stats, equal);
    expect(stats.hashCode, equal.hashCode);
    expect(
      stats,
      isNot(CommuteStats(medianDuration: Duration.zero, sampleSize: 3)),
    );
    expect(
      stats,
      isNot(CommuteStats(medianDuration: stats.medianDuration, sampleSize: 4)),
    );
    expect(
      () => CommuteStats(
        medianDuration: const Duration(microseconds: -1),
        sampleSize: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => CommuteStats(medianDuration: Duration.zero, sampleSize: -1),
      throwsArgumentError,
    );
  });
}
