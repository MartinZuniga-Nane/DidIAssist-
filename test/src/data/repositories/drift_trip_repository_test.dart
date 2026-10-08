import 'package:did_i_attend/src/data/database/app_database.dart';
import 'package:did_i_attend/src/data/repositories/drift_trip_repository.dart';
import 'package:did_i_attend/src/domain/models/travel_mode.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../domain/models/fixtures.dart';
import '../database/test_database.dart';

void main() {
  late AppDatabase database;
  late DriftTripRepository repository;

  setUp(() {
    database = createTestDatabase();
    repository = DriftTripRepository(database);
  });
  tearDown(() => database.close());

  test('empty history and missing directed pair', () async {
    expect(
      await repository.getRecent(fromPlaceId: homeId, toPlaceId: placeId),
      isEmpty,
    );
    await repository.add(sampleTrip());
    expect(
      await repository.getRecent(fromPlaceId: placeId, toPlaceId: homeId),
      isEmpty,
    );
    expect(
      await repository.getRecent(fromPlaceId: 'missing', toPlaceId: placeId),
      isEmpty,
    );
  });

  test('add is idempotent and never replaces a duplicate trip ID', () async {
    final trip = sampleTrip();
    await repository.add(trip);
    await repository.add(
      trip.copyWith(
        mode: () => TravelMode.walking,
        arrivedAt: trip.arrivedAt.add(const Duration(minutes: 10)),
      ),
    );
    expect(
      await repository.getRecent(fromPlaceId: homeId, toPlaceId: placeId),
      [trip],
    );
    expect(await database.select(database.trips).get(), hasLength(1));
  });

  test('parallel duplicate adds preserve original trip', () async {
    final trip = sampleTrip();
    await Future.wait([
      repository.add(trip),
      repository.add(trip.copyWith(mode: () => null)),
    ]);
    expect(
      await repository.getRecent(fromPlaceId: homeId, toPlaceId: placeId),
      [trip],
    );
  });

  test(
    'recent trips order newest arrival first then ID and honor limits',
    () async {
      final original = sampleTrip();
      final older = original.copyWith(
        id: 'older',
        arrivedAt: original.arrivedAt.subtract(const Duration(milliseconds: 1)),
      );
      final a = original.copyWith(id: 'a');
      final b = original.copyWith(id: 'b');
      final newer = original.copyWith(
        id: 'newer',
        arrivedAt: original.arrivedAt.add(const Duration(milliseconds: 1)),
      );
      for (final trip in [
        b,
        older,
        newer,
        a,
        original.copyWith(
          id: 'reverse',
          fromPlaceId: placeId,
          toPlaceId: homeId,
        ),
      ]) {
        await repository.add(trip);
      }
      expect(
        await repository.getRecent(fromPlaceId: homeId, toPlaceId: placeId),
        [newer, a, b, older],
      );
      expect(
        await repository.getRecent(
          fromPlaceId: homeId,
          toPlaceId: placeId,
          limit: 2,
        ),
        [newer, a],
      );
      expect(
        await repository.getRecent(
          fromPlaceId: homeId,
          toPlaceId: placeId,
          limit: 0,
        ),
        isEmpty,
      );
      expect(
        await repository.getRecent(
          fromPlaceId: homeId,
          toPlaceId: placeId,
          limit: 99,
        ),
        [newer, a, b, older],
      );
      expect(
        () => repository.getRecent(
          fromPlaceId: homeId,
          toPlaceId: placeId,
          limit: -1,
        ),
        throwsRangeError,
      );
    },
  );

  test(
    'null limit includes all history without commute-duration validation',
    () async {
      for (var index = 0; index < 12; index++) {
        final departure = DateTime.utc(2026, 10, index + 1, 8);
        await repository.add(
          sampleTrip().copyWith(
            id: 'trip-$index',
            departedAt: departure,
            arrivedAt: departure.add(Duration(minutes: index == 0 ? 181 : 1)),
          ),
        );
      }
      final trips = await repository.getRecent(
        fromPlaceId: homeId,
        toPlaceId: placeId,
      );
      expect(trips, hasLength(12));
      expect(trips.first.id, 'trip-11');
      expect(trips.last.duration.inMinutes, 181);
    },
  );

  test(
    'stores nullable mode and normalizes instants to UTC milliseconds',
    () async {
      final trip = sampleTrip().copyWith(
        mode: () => null,
        departedAt: DateTime(2026, 10, 5, 8, 0, 0, 123),
        arrivedAt: DateTime(2026, 10, 5, 8, 30, 0, 456),
      );
      await repository.add(trip);
      final stored = (await repository.getRecent(
        fromPlaceId: homeId,
        toPlaceId: placeId,
      )).single;
      expect(stored, trip);
      expect(stored.departedAt.isUtc, isTrue);
      expect(stored.arrivedAt.isUtc, isTrue);
    },
  );
}
