import 'package:clock/clock.dart';
import 'package:did_i_attend/src/app/class_sample_scheduler.dart';
import 'package:did_i_attend/src/data/database/app_database.dart';
import 'package:did_i_attend/src/data/repositories/drift_class_sample_schedule_store.dart';
import 'package:did_i_attend/src/data/repositories/drift_course_repository.dart';
import 'package:did_i_attend/src/data/repositories/drift_place_repository.dart';
import 'package:did_i_attend/src/data/repositories/drift_settings_repository.dart';
import 'package:did_i_attend/src/domain/models/models.dart';
import 'package:did_i_attend/src/domain/services/class_sample_planner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/database/test_database.dart';
import '../domain/services/fixtures.dart';
import 'fakes.dart';

void main() {
  late AppDatabase database;
  late DriftCourseRepository courses;
  late DriftPlaceRepository places;
  late DriftSettingsRepository settings;
  late DriftClassSampleScheduleStore store;
  late FakeClassSampleGateway gateway;
  late DateTime now;
  final source = occurrence();

  ClassSampleScheduler scheduler() => ClassSampleScheduler(
    courses: courses,
    places: places,
    settings: settings,
    store: store,
    gateway: gateway,
    timeSource: Clock(() => now),
  );

  setUp(() async {
    database = createTestDatabase();
    courses = DriftCourseRepository(database);
    places = DriftPlaceRepository(database);
    settings = DriftSettingsRepository(database);
    store = DriftClassSampleScheduleStore(database);
    gateway = FakeClassSampleGateway();
    now = DateTime(2026, 10, 5, 8, 30);
    await places.save(source.place);
    await courses.saveCourse(source.course);
    await courses.saveSlot(source.slot);
  });
  tearDown(() => database.close());

  test(
    'new tasks replace, persisted unchanged tasks keep across instances',
    () async {
      final first = await scheduler().sync();
      expect(first.replace, hasLength(2));
      expect(await store.load(), hasLength(2));
      store = DriftClassSampleScheduleStore(database);
      final next = await scheduler().sync();
      expect(next.keep, hasLength(2));
      expect(next.replace, isEmpty);
      expect(gateway.decisions.map((entry) => entry.$2), [
        ClassSampleSchedulePolicy.replace,
        ClassSampleSchedulePolicy.replace,
        ClassSampleSchedulePolicy.keep,
        ClassSampleSchedulePolicy.keep,
      ]);
    },
  );

  test(
    'changed start replaces stable names and removes deleted occurrences',
    () async {
      final original = (await scheduler().sync()).replace;
      await courses.saveSlot(source.slot.copyWith(startMinute: 600));
      final changed = await scheduler().sync();
      expect(changed.replace, hasLength(2));
      expect(
        changed.replace.map((task) => task.uniqueName),
        original.map((task) => task.uniqueName),
      );
      expect(changed.replace.first.runAt, DateTime(2026, 10, 5, 10, 1).toUtc());
      await courses.deleteCourse(source.course.id);
      final deleted = await scheduler().sync();
      expect(deleted.cancel, hasLength(2));
      expect(
        gateway.canceled.toSet(),
        original.map((task) => task.uniqueName).toSet(),
      );
      expect(await store.load(), isEmpty);
      expect(gateway.tasks, isEmpty);
    },
  );

  test('policy changes keep the first offset and replace the second', () async {
    await scheduler().sync();
    await settings.save(
      UserSettings(attendancePolicy: AttendancePolicy(graceMinutes: 5)),
    );
    final plan = await scheduler().sync();
    expect(plan.keep.single.offsetMinutes, 1);
    expect(plan.replace.single.offsetMinutes, 3);
    expect(plan.cancel.single.offsetMinutes, 8);
  });

  test(
    'partially applied plugin operations roll back ledger and can retry',
    () async {
      await scheduler().sync();
      await courses.saveSlot(source.slot.copyWith(startMinute: 600));
      final old = await store.load();
      gateway.failScheduling = true;
      await expectLater(scheduler().sync(), throwsStateError);
      expect(await store.load(), old);
      gateway.failScheduling = false;
      expect((await scheduler().sync()).replace, hasLength(2));
    },
  );

  test(
    'parallel reconciliations serialize into one replace and one keep',
    () async {
      final results = await Future.wait([
        scheduler().sync(),
        scheduler().sync(),
      ]);
      expect(results.first.replace, hasLength(2));
      expect(results.last.keep, hasLength(2));
      expect(await store.load(), hasLength(2));
    },
  );

  test(
    'elapsed samples cancel while upcoming offsets remain scheduled',
    () async {
      await scheduler().sync();
      now = DateTime(2026, 10, 5, 9, 3);
      final plan = await scheduler().sync();
      expect(plan.cancel.single.offsetMinutes, 1);
      expect(plan.keep.single.offsetMinutes, 8);
    },
  );

  test(
    'ledger fields round-trip without losing local date or UTC precision',
    () async {
      final task = ClassSampleTask(
        slotId: source.slot.id,
        date: source.occurrenceDate,
        offsetMinutes: 1,
        classStart: source.start.add(const Duration(milliseconds: 123)),
        runAt: source.start.add(const Duration(minutes: 1, milliseconds: 456)),
      );
      await store.save(task);
      expect((await store.load()).single, task);
      final row = await database.select(database.classSampleTasks).getSingle();
      expect(row.occurrenceDate, '2026-10-05');
      expect(row.classStart, task.classStart.millisecondsSinceEpoch);
      expect(row.runAt, task.runAt.millisecondsSinceEpoch);
      await store.delete(task.uniqueName);
      expect(await store.load(), isEmpty);
    },
  );
}
