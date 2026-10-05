import 'dart:async';

import 'package:did_i_assist/src/core/local_date.dart';
import 'package:did_i_assist/src/data/database/app_database.dart';
import 'package:did_i_assist/src/data/database/mappers/attendance_record_mapping.dart';
import 'package:did_i_assist/src/data/database/mappers/place_mapping.dart';
import 'package:did_i_assist/src/data/repositories/drift_course_repository.dart';
import 'package:did_i_assist/src/domain/models/course.dart';
import 'package:did_i_assist/src/domain/models/schedule_slot.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../domain/models/fixtures.dart';
import '../database/test_database.dart';

void main() {
  late AppDatabase database;
  late DriftCourseRepository repository;

  setUp(() {
    database = createTestDatabase();
    repository = DriftCourseRepository(database);
  });
  tearDown(() => database.close());

  Future<void> seedCourse() async {
    await database
        .into(database.places)
        .insert(placeToCompanion(samplePlace()));
    await repository.saveCourse(sampleCourse());
  }

  test('empty and missing reads and deletes', () async {
    expect(await repository.getAll(), isEmpty);
    expect(await repository.getById('missing'), isNull);
    expect(await repository.getSlots(), isEmpty);
    expect(await repository.getSlots(courseId: 'missing'), isEmpty);
    await repository.deleteCourse('missing');
    await repository.deleteSlot('missing');
  });

  test(
    'courses save by ID and clear nullable bounds without deleting slots',
    () async {
      await seedCourse();
      await repository.saveSlot(sampleSlot());
      final dated = sampleCourse().copyWith(
        activeFrom: () => LocalDate(2026, 1, 1),
      );
      await repository.saveCourse(dated);
      expect(await repository.getById(courseId), dated);
      await repository.saveCourse(sampleCourse().copyWith(id: 'z', name: 'Z'));
      await repository.saveCourse(
        sampleCourse().copyWith(id: 'a', name: 'Mathematics'),
      );
      await repository.saveCourse(sampleCourse());
      expect((await repository.getAll()).map((course) => course.id), [
        courseId,
        'a',
        'z',
      ]);
      expect(await repository.getById(courseId), sampleCourse());
      expect(await repository.getSlots(), [sampleSlot()]);
    },
  );

  test(
    'slots insert, update, filter and order by weekday, minute and ID',
    () async {
      await seedCourse();
      await repository.saveCourse(sampleCourse().copyWith(id: 'other'));
      final slots = [
        sampleSlot().copyWith(id: 'z', weekday: 2),
        sampleSlot().copyWith(id: 'b', courseId: 'other', startMinute: 480),
        sampleSlot().copyWith(id: 'a', startMinute: 480),
        sampleSlot().copyWith(id: 'c', startMinute: 700),
      ];
      for (final slot in slots) {
        await repository.saveSlot(slot);
      }
      expect((await repository.getSlots()).map((slot) => slot.id), [
        'a',
        'b',
        'c',
        'z',
      ]);
      expect(
        (await repository.getSlots(courseId: courseId)).map((slot) => slot.id),
        ['a', 'c', 'z'],
      );
      final updated = slots.last.copyWith(
        startMinute: 400,
        durationMinutes: 45,
      );
      await repository.saveSlot(updated);
      expect((await repository.getSlots()).first, updated);
      await repository.deleteSlot('c');
      expect((await repository.getSlots()).map((slot) => slot.id), [
        'a',
        'b',
        'z',
      ]);
    },
  );

  test(
    'course deletion cascades only its slots and preserves attendance',
    () async {
      await seedCourse();
      await repository.saveCourse(sampleCourse().copyWith(id: 'other'));
      await repository.saveSlot(sampleSlot());
      final otherSlot = sampleSlot().copyWith(id: 'other', courseId: 'other');
      await repository.saveSlot(otherSlot);
      await database
          .into(database.attendanceRecords)
          .insert(attendanceRecordToCompanion(sampleAttendance()));
      await repository.deleteCourse(courseId);
      expect(await repository.getById(courseId), isNull);
      expect(await repository.getSlots(courseId: courseId), isEmpty);
      expect(await repository.getSlots(), [otherSlot]);
      expect(
        attendanceRecordFromRow(
          await database.select(database.attendanceRecords).getSingle(),
        ),
        sampleAttendance(),
      );
    },
  );

  test('slot deletion preserves attendance and its course', () async {
    await seedCourse();
    await repository.saveSlot(sampleSlot());
    await database
        .into(database.attendanceRecords)
        .insert(attendanceRecordToCompanion(sampleAttendance()));
    await repository.deleteSlot(slotId);
    expect(await repository.getSlots(), isEmpty);
    expect(await repository.getById(courseId), sampleCourse());
    expect(
      await database.select(database.attendanceRecords).get(),
      hasLength(1),
    );
  });

  test('watchAll emits course insert, update and deletion', () async {
    final iterator = StreamIterator<List<Course>>(repository.watchAll());
    addTearDown(iterator.cancel);
    expect(
      await iterator.moveNext().timeout(const Duration(seconds: 5)),
      isTrue,
    );
    expect(iterator.current, isEmpty);
    await repository.saveCourse(sampleCourse());
    expect(
      await iterator.moveNext().timeout(const Duration(seconds: 5)),
      isTrue,
    );
    expect(iterator.current, [sampleCourse()]);
    final updated = sampleCourse().copyWith(name: 'Updated');
    await repository.saveCourse(updated);
    expect(
      await iterator.moveNext().timeout(const Duration(seconds: 5)),
      isTrue,
    );
    expect(iterator.current, [updated]);
    await repository.deleteCourse(courseId);
    expect(
      await iterator.moveNext().timeout(const Duration(seconds: 5)),
      isTrue,
    );
    expect(iterator.current, isEmpty);
  });

  for (final filter in [null, courseId]) {
    test(
      'watchSlots($filter) emits insert, update, delete and cascade',
      () async {
        await seedCourse();
        final iterator = StreamIterator<List<ScheduleSlot>>(
          repository.watchSlots(courseId: filter),
        );
        addTearDown(iterator.cancel);
        expect(
          await iterator.moveNext().timeout(const Duration(seconds: 5)),
          isTrue,
        );
        expect(iterator.current, isEmpty);
        await repository.saveSlot(sampleSlot());
        expect(
          await iterator.moveNext().timeout(const Duration(seconds: 5)),
          isTrue,
        );
        expect(iterator.current, [sampleSlot()]);
        final updated = sampleSlot().copyWith(startMinute: 600);
        await repository.saveSlot(updated);
        expect(
          await iterator.moveNext().timeout(const Duration(seconds: 5)),
          isTrue,
        );
        expect(iterator.current, [updated]);
        await repository.deleteSlot(slotId);
        expect(
          await iterator.moveNext().timeout(const Duration(seconds: 5)),
          isTrue,
        );
        expect(iterator.current, isEmpty);
        await repository.saveSlot(sampleSlot());
        expect(
          await iterator.moveNext().timeout(const Duration(seconds: 5)),
          isTrue,
        );
        await repository.deleteCourse(courseId);
        expect(
          await iterator.moveNext().timeout(const Duration(seconds: 5)),
          isTrue,
        );
        expect(iterator.current, isEmpty);
      },
    );
  }

  test('watchSlots applies its course filter', () async {
    await seedCourse();
    await repository.saveCourse(sampleCourse().copyWith(id: 'other'));
    await repository.saveSlot(
      sampleSlot().copyWith(id: 'other', courseId: 'other'),
    );
    await repository.saveSlot(sampleSlot());
    expect(await repository.watchSlots(courseId: courseId).first, [
      sampleSlot(),
    ]);
  });
}
