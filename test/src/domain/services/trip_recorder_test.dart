import 'package:clock/clock.dart';
import 'package:did_i_attend/src/domain/models/models.dart';
import 'package:did_i_attend/src/domain/services/trip_detector.dart';
import 'package:did_i_attend/src/domain/services/trip_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';
import 'in_memory_repositories.dart';

void main() {
  final now = DateTime(2026, 10, 12, 10);
  final departed = DateTime(2026, 10, 5, 10);
  final exit = transition(LocationEventType.geofenceExit, departed);
  final enter = transition(
    LocationEventType.geofenceEnter,
    departed.add(const Duration(minutes: 30)),
    placeId: 'campus',
  );
  late InMemoryLocationEventRepository events;
  late InMemoryPlaceRepository places;
  late InMemoryTripRepository trips;
  late TripRecorder recorder;

  setUp(() {
    events = InMemoryLocationEventRepository([enter, exit]);
    places = InMemoryPlaceRepository([homePlace(), campusPlace()]);
    trips = InMemoryTripRepository();
    recorder = TripRecorder(
      locationEventRepository: events,
      placeRepository: places,
      tripRepository: trips,
      timeSource: Clock.fixed(now),
    );
  });

  test('records new trips with default seven-day UTC query bounds', () async {
    final recorded = await recorder.recordRecent();
    expect(recorded.single.duration, const Duration(minutes: 30));
    expect(trips.trips.values, recorded);
    expect(trips.added, recorded);
    expect(events.queriedFrom, now.subtract(const Duration(days: 7)).toUtc());
    expect(events.queriedUntil, now.toUtc());
    expect(events.queriedFrom!.isUtc, isTrue);
    expect(events.queriedUntil!.isUtc, isTrue);
    expect(trips.queries, [('home', 'campus', null)]);
  });

  test(
    'repeated recording returns no new trips and does not add again',
    () async {
      final first = await recorder.recordRecent();
      expect(first, hasLength(1));
      expect(await recorder.recordRecent(), isEmpty);
      expect(trips.trips, hasLength(1));
      expect(trips.added, hasLength(1));
      await events.append(
        enter.copyWith(
          id: 'later-dwell',
          type: LocationEventType.geofenceDwell,
          recordedAt: enter.recordedAt.add(const Duration(minutes: 5)),
        ),
      );
      expect(await recorder.recordRecent(), isEmpty);
      expect(trips.trips.values.single, first.single);
    },
  );

  test('custom lookback excludes a departure before the lower bound', () async {
    expect(
      await recorder.recordRecent(lookback: const Duration(days: 1)),
      isEmpty,
    );
    expect(events.queriedFrom, now.subtract(const Duration(days: 1)).toUtc());
    expect(trips.added, isEmpty);
  });

  test(
    'query includes the lower bound and excludes an arrival at now',
    () async {
      events.events.clear();
      await events.append(
        exit.copyWith(recordedAt: now.subtract(const Duration(minutes: 30))),
      );
      await events.append(enter.copyWith(recordedAt: now));
      expect(
        await recorder.recordRecent(lookback: const Duration(minutes: 30)),
        isEmpty,
      );
      await events.append(
        enter.copyWith(
          id: 'arrival-before-now',
          recordedAt: now.subtract(const Duration(microseconds: 1)),
        ),
      );
      final recorded = await recorder.recordRecent(
        lookback: const Duration(minutes: 30),
      );
      expect(
        recorded.single.duration,
        const Duration(minutes: 30, microseconds: -1),
      );
    },
  );

  test(
    'existing IDs beyond the latest ten trips are still idempotent',
    () async {
      final existing = const TripDetector()
          .detect(
            events: [exit, enter],
            places: places.places.values,
          )
          .single;
      trips.trips[existing.id] = existing;
      for (var i = 0; i < 12; i++) {
        final newer = commute(
          id: 'newer-$i',
          duration: const Duration(minutes: 20),
          arrivedAt: departed.add(Duration(hours: i + 1)),
        );
        trips.trips[newer.id] = newer;
      }
      expect(await recorder.recordRecent(), isEmpty);
      expect(trips.added, isEmpty);
      expect(trips.queries.single.$3, isNull);
    },
  );

  test('multiple trips for a pair query existing IDs once per run', () async {
    await events.append(
      exit.copyWith(
        id: 'second-exit',
        recordedAt: departed.add(const Duration(days: 1)),
      ),
    );
    await events.append(
      enter.copyWith(
        id: 'second-enter',
        recordedAt: enter.recordedAt.add(const Duration(days: 1)),
      ),
    );
    final recorded = await recorder.recordRecent();
    expect(recorded, hasLength(2));
    expect(trips.queries, hasLength(1));
    expect(recorded.map((trip) => trip.id).toSet(), hasLength(2));
  });

  test('each directed home and campus pair has separate known IDs', () async {
    await places.save(homePlace(id: 'other-home'));
    await places.save(campusPlace(id: 'other-campus'));
    await events.append(
      exit.copyWith(
        id: 'other-exit',
        placeId: () => 'other-home',
        recordedAt: departed.add(const Duration(days: 1)),
      ),
    );
    await events.append(
      enter.copyWith(
        id: 'other-enter',
        placeId: () => 'other-campus',
        recordedAt: enter.recordedAt.add(const Duration(days: 1)),
      ),
    );
    expect(await recorder.recordRecent(), hasLength(2));
    expect(trips.queries, [
      ('home', 'campus', null),
      ('other-home', 'other-campus', null),
    ]);
    expect(await recorder.recordRecent(), isEmpty);
  });

  test(
    'missing places and incomplete or invalid evidence add nothing',
    () async {
      await places.delete('home');
      expect(await recorder.recordRecent(), isEmpty);
      expect(trips.queries, isEmpty);
      await places.save(homePlace());
      events.events.remove(enter.id);
      expect(await recorder.recordRecent(), isEmpty);
      await events.append(
        enter.copyWith(
          recordedAt: departed.add(const Duration(minutes: 2)),
        ),
      );
      expect(await recorder.recordRecent(), isEmpty);
      expect(trips.added, isEmpty);
    },
  );

  test(
    'negative lookback fails before querying and zero lookback is empty',
    () async {
      await expectLater(
        recorder.recordRecent(lookback: const Duration(microseconds: -1)),
        throwsArgumentError,
      );
      expect(events.queriedUntil, isNull);
      expect(await recorder.recordRecent(lookback: Duration.zero), isEmpty);
      expect(events.queriedFrom, events.queriedUntil);
    },
  );
}
