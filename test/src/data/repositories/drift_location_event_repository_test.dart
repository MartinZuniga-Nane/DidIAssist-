import 'package:did_i_assist/src/data/database/app_database.dart';
import 'package:did_i_assist/src/data/repositories/drift_location_event_repository.dart';
import 'package:did_i_assist/src/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../domain/models/fixtures.dart';
import '../database/test_database.dart';

void main() {
  late AppDatabase database;
  late DriftLocationEventRepository repository;
  final start = DateTime.utc(2026, 10, 5, 9, 0, 0, 123);
  final until = start.add(const Duration(hours: 1));

  setUp(() {
    database = createTestDatabase();
    repository = DriftLocationEventRepository(database);
  });
  tearDown(() => database.close());

  for (final epochOffset in [123, -123]) {
    test(
      'submillisecond bounds preserve half-open inclusion at $epochOffset',
      () async {
        final firstInstant = DateTime.fromMillisecondsSinceEpoch(
          epochOffset,
          isUtc: true,
        );
        final nextInstant = firstInstant.add(const Duration(milliseconds: 1));
        final first = sampleEvent().copyWith(
          id: 'first',
          recordedAt: firstInstant,
        );
        final next = first.copyWith(id: 'next', recordedAt: nextInstant);
        await repository.append(first);
        await repository.append(next);
        final between = firstInstant.add(const Duration(microseconds: 500));
        expect(
          await repository.query(
            from: between,
            until: nextInstant.add(const Duration(milliseconds: 1)),
          ),
          [next],
        );
        expect(
          await repository.query(from: firstInstant, until: between),
          [first],
        );
      },
    );
  }

  test('empty queries include null from', () async {
    expect(await repository.query(until: until), isEmpty);
    expect(
      await repository.query(from: start, until: until, placeId: placeId),
      isEmpty,
    );
  });

  test('append is idempotent and preserves original evidence', () async {
    final event = sampleEvent();
    await repository.append(event);
    await repository.append(
      event.copyWith(type: LocationEventType.geofenceExit, recordedAt: until),
    );
    expect(await repository.query(until: until), [event]);
    expect(await database.select(database.locationEvents).get(), hasLength(1));
  });

  test('parallel duplicate appends keep only the first evidence', () async {
    final first = sampleEvent();
    await Future.wait([
      repository.append(first),
      repository.append(first.copyWith(type: LocationEventType.geofenceExit)),
    ]);
    expect(await repository.query(until: until), [first]);
  });

  test(
    'query is half-open and orders equal millisecond instants by ID',
    () async {
      final events = [
        sampleEvent().copyWith(id: 'until', recordedAt: until),
        sampleEvent().copyWith(id: 'b', recordedAt: start),
        sampleEvent().copyWith(
          id: 'middle',
          recordedAt: start.add(const Duration(milliseconds: 1)),
        ),
        sampleEvent().copyWith(
          id: 'before',
          recordedAt: start.subtract(const Duration(milliseconds: 1)),
        ),
        sampleEvent().copyWith(id: 'a', recordedAt: start),
      ];
      for (final event in events) {
        await repository.append(event);
      }
      expect(
        (await repository.query(
          from: start,
          until: until,
        )).map((event) => event.id),
        ['a', 'b', 'middle'],
      );
      expect(await repository.query(from: start, until: start), isEmpty);
      expect(await repository.query(from: until, until: start), isEmpty);
    },
  );

  test(
    'null from returns all preceding history including pre-epoch events',
    () async {
      final ancient = sampleEvent().copyWith(
        id: 'ancient',
        recordedAt: DateTime.fromMillisecondsSinceEpoch(-123, isUtc: true),
      );
      final before = sampleEvent().copyWith(
        id: 'before',
        recordedAt: start.subtract(const Duration(days: 30)),
      );
      final inside = sampleEvent().copyWith(id: 'inside', recordedAt: start);
      for (final event in [inside, before, ancient]) {
        await repository.append(event);
      }
      expect(await repository.query(until: until), [ancient, before, inside]);
      expect(await repository.query(from: start, until: until), [inside]);
    },
  );

  test(
    'place filter retains every position sample regardless of place ID',
    () async {
      final events = [
        sampleEvent().copyWith(
          id: 'enter',
          type: LocationEventType.geofenceEnter,
          recordedAt: start,
        ),
        sampleEvent().copyWith(
          id: 'exit',
          type: LocationEventType.geofenceExit,
          recordedAt: start,
        ),
        sampleEvent().copyWith(
          id: 'dwell',
          type: LocationEventType.geofenceDwell,
          recordedAt: start,
        ),
        sampleEvent().copyWith(
          id: 'other',
          placeId: () => homeId,
          recordedAt: start,
        ),
        sampleEvent().copyWith(
          id: 'null-sample',
          type: LocationEventType.positionSample,
          placeId: () => null,
          recordedAt: start,
        ),
        sampleEvent().copyWith(
          id: 'other-sample',
          type: LocationEventType.positionSample,
          placeId: () => homeId,
          recordedAt: start,
        ),
        sampleEvent().copyWith(
          id: 'own-sample',
          type: LocationEventType.positionSample,
          recordedAt: start,
        ),
        sampleEvent().copyWith(
          id: 'outside-range',
          type: LocationEventType.positionSample,
          recordedAt: until,
        ),
      ];
      for (final event in events) {
        await repository.append(event);
      }
      expect(
        (await repository.query(
          from: start,
          until: until,
          placeId: placeId,
        )).map((event) => event.id),
        ['dwell', 'enter', 'exit', 'null-sample', 'other-sample', 'own-sample'],
      );
      expect(
        (await repository.query(
          until: until,
          placeId: 'missing',
        )).map((event) => event.id),
        ['null-sample', 'other-sample', 'own-sample'],
      );
      expect(await repository.query(from: start, until: until), hasLength(7));
    },
  );

  test(
    'query normalizes local bounds to UTC and preserves milliseconds',
    () async {
      final localStart = DateTime(2026, 10, 5, 9, 0, 0, 123);
      final localUntil = localStart.add(const Duration(milliseconds: 1));
      final first = sampleEvent().copyWith(id: 'first', recordedAt: localStart);
      final excluded = first.copyWith(id: 'excluded', recordedAt: localUntil);
      await repository.append(first);
      await repository.append(excluded);
      final localResult = await repository.query(
        from: localStart,
        until: localUntil,
      );
      expect(localResult, [first]);
      expect(
        localResult,
        await repository.query(
          from: localStart.toUtc(),
          until: localUntil.toUtc(),
        ),
      );
      expect(localResult.single.recordedAt.isUtc, isTrue);
    },
  );
}
