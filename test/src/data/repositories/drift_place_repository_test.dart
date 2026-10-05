import 'dart:async';

import 'package:did_i_assist/src/data/database/app_database.dart';
import 'package:did_i_assist/src/data/database/mappers/course_mapping.dart';
import 'package:did_i_assist/src/data/database/mappers/schedule_slot_mapping.dart';
import 'package:did_i_assist/src/data/repositories/drift_place_repository.dart';
import 'package:did_i_assist/src/data/repositories/place_in_use_exception.dart';
import 'package:did_i_assist/src/domain/models/place.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../domain/models/fixtures.dart';
import '../database/test_database.dart';

void main() {
  late AppDatabase database;
  late DriftPlaceRepository repository;

  setUp(() {
    database = createTestDatabase();
    repository = DriftPlaceRepository(database);
  });
  tearDown(() => database.close());

  test('empty reads and deletion of a missing place', () async {
    expect(await repository.getById('missing'), isNull);
    expect(await repository.getAll(), isEmpty);
    await repository.delete('missing');
  });

  test('save inserts and updates by ID with deterministic ordering', () async {
    final original = samplePlace();
    final updated = original.copyWith(name: 'A', radiusMeters: 321.5);
    final other = original.copyWith(id: 'a', name: 'A');
    final last = original.copyWith(id: 'z', name: 'Z');
    await repository.save(original);
    expect(await repository.getById(original.id), original);
    await repository.save(last);
    await repository.save(other);
    await repository.save(updated);
    expect(await repository.getAll(), [updated, other, last]);
    expect(await repository.getById(original.id), updated);
    await repository.delete(original.id);
    expect(await repository.getById(original.id), isNull);
    expect(await repository.getAll(), [other, last]);
  });

  test(
    'restrict reports a clear exception and leaves the place intact',
    () async {
      await repository.save(samplePlace());
      await database
          .into(database.courses)
          .insert(courseToCompanion(sampleCourse()));
      await database
          .into(database.scheduleSlots)
          .insert(scheduleSlotToCompanion(sampleSlot()));
      await expectLater(
        repository.delete(placeId),
        throwsA(
          isA<PlaceInUseException>().having(
            (error) => error.placeId,
            'placeId',
            placeId,
          ),
        ),
      );
      expect(
        const PlaceInUseException(placeId).toString(),
        contains('schedule slots'),
      );
      expect(await repository.getById(placeId), samplePlace());
      await database.delete(database.scheduleSlots).go();
      await repository.delete(placeId);
      expect(await repository.getAll(), isEmpty);
    },
  );

  test(
    'watchAll emits initially and after insert, update and deletion',
    () async {
      final iterator = StreamIterator<List<Place>>(repository.watchAll());
      addTearDown(iterator.cancel);
      expect(
        await iterator.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
      expect(iterator.current, isEmpty);
      await repository.save(samplePlace());
      expect(
        await iterator.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
      expect(iterator.current, [samplePlace()]);
      final updated = samplePlace().copyWith(name: 'Updated');
      await repository.save(updated);
      expect(
        await iterator.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
      expect(iterator.current, [updated]);
      await repository.delete(placeId);
      expect(
        await iterator.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
      expect(iterator.current, isEmpty);
    },
  );
}
