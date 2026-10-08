import 'package:did_i_attend/src/core/local_date.dart';
import 'package:did_i_attend/src/domain/models/models.dart';
import 'package:did_i_attend/src/domain/services/class_sample_planner.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  const planner = ClassSamplePlanner();

  test('default offsets are one and eight minutes with stable names', () {
    final source = occurrence();
    final tasks = planner.tasks(
      occurrences: [source],
      policy: AttendancePolicy(),
      now: DateTime(2026, 10, 5, 8),
    );
    expect(tasks.map((task) => task.offsetMinutes), [1, 8]);
    expect(tasks.map((task) => task.uniqueName), [
      'did_i_attend.class_sample.slot.2026-10-05.1',
      'did_i_attend.class_sample.slot.2026-10-05.8',
    ]);
    expect(tasks.first.runAt, DateTime(2026, 10, 5, 9, 1).toUtc());
    expect(tasks.last.runAt, DateTime(2026, 10, 5, 9, 8).toUtc());
    expect(
      tasks,
      planner.tasks(
        occurrences: [source, source],
        policy: AttendancePolicy(),
        now: DateTime(2026, 10, 5, 8),
      ),
    );
    expect(tasks.clear, throwsUnsupportedError);
  });

  for (final grace in [0, 1, 2, 3, 4]) {
    test('small grace $grace retains two distinct offsets', () {
      final tasks = planner.tasks(
        occurrences: [occurrence()],
        policy: AttendancePolicy(graceMinutes: grace),
        now: DateTime(2026, 10, 5, 8),
      );
      expect(tasks.map((task) => task.offsetMinutes), [1, 2]);
    });
  }

  test(
    'occurrence horizon is half-open and samples may follow its boundary',
    () {
      final now = DateTime(2026, 10, 5, 9);
      final until = now.add(const Duration(hours: 24));
      final before = occurrence(
        start: until.subtract(const Duration(minutes: 1)),
      );
      final excluded = occurrence(start: until);
      final tasks = planner.tasks(
        occurrences: [before, excluded],
        policy: AttendancePolicy(),
        now: now,
      );
      expect(tasks, hasLength(2));
      expect(tasks.first.runAt, until.toUtc());
      expect(tasks.last.runAt.isAfter(until), isTrue);
      expect(
        tasks.every((task) => task.classStart == before.start.toUtc()),
        isTrue,
      );
    },
  );

  test('already-started classes retain future fallback samples', () {
    final tasks = planner.tasks(
      occurrences: [occurrence()],
      policy: AttendancePolicy(),
      now: DateTime(2026, 10, 5, 9, 3),
    );
    expect(tasks.map((task) => task.offsetMinutes), [8]);
    expect(
      planner.tasks(
        occurrences: [occurrence()],
        policy: AttendancePolicy(),
        now: DateTime(2026, 10, 5, 11),
      ),
      isEmpty,
    );
  });

  test('overnight offsets retain the occurrence date and cross midnight', () {
    final source = occurrence(start: DateTime(2026, 12, 31, 23, 58));
    final tasks = planner.tasks(
      occurrences: [source],
      policy: AttendancePolicy(),
      now: DateTime(2026, 12, 31, 22),
    );
    expect(tasks.first.runAt, DateTime(2026, 12, 31, 23, 59).toUtc());
    expect(tasks.last.runAt, DateTime(2027, 1, 1, 0, 6).toUtc());
    expect(tasks.last.date, LocalDate(2026, 12, 31));
  });

  for (final date in [LocalDate(2026, 9, 6), LocalDate(2026, 4, 5)]) {
    test('DST boundary $date uses local constructors for both offsets', () {
      final place = campusPlace();
      final course = Course(id: 'course', name: 'Mathematics');
      final slot = ScheduleSlot(
        id: 'slot',
        courseId: course.id,
        placeId: place.id,
        weekday: date.weekday,
        startMinute: 0,
        durationMinutes: 120,
      );
      final source = ClassOccurrence.forDate(
        slot: slot,
        course: course,
        place: place,
        date: date,
      );
      final tasks = planner.tasks(
        occurrences: [source],
        policy: AttendancePolicy(),
        now: DateTime(
          date.year,
          date.month,
          date.day,
        ).subtract(const Duration(hours: 2)),
      );
      expect(tasks.map((task) => task.runAt), [
        DateTime(date.year, date.month, date.day, 0, 1).toUtc(),
        DateTime(date.year, date.month, date.day, 0, 8).toUtc(),
      ]);
      expect(tasks.every((task) => task.date == date), isTrue);
    });
  }

  test(
    'reconcile keeps unchanged, replaces changed and cancels removed tasks',
    () {
      final original = planner.tasks(
        occurrences: [occurrence()],
        policy: AttendancePolicy(),
        now: DateTime(2026, 10, 5, 8),
      );
      final changed = ClassSampleTask(
        slotId: original.last.slotId,
        date: original.last.date,
        offsetMinutes: original.last.offsetMinutes,
        classStart: original.last.classStart.add(const Duration(minutes: 10)),
        runAt: original.last.runAt.add(const Duration(minutes: 10)),
      );
      final removed = ClassSampleTask(
        slotId: 'removed',
        date: original.first.date,
        offsetMinutes: 1,
        classStart: original.first.classStart,
        runAt: original.first.runAt,
      );
      final plan = planner.reconcile(
        desired: [original.first, changed],
        existing: [...original, removed],
      );
      expect(plan.keep, [original.first]);
      expect(plan.replace, [changed]);
      expect(plan.cancel, [removed]);
      expect(changed.uniqueName, original.last.uniqueName);
    },
  );

  test('grace changes cancel an old offset and register the new one', () {
    final original = planner.tasks(
      occurrences: [occurrence()],
      policy: AttendancePolicy(),
      now: DateTime(2026, 10, 5, 8),
    );
    final desired = planner.tasks(
      occurrences: [occurrence()],
      policy: AttendancePolicy(graceMinutes: 5),
      now: DateTime(2026, 10, 5, 8),
    );
    final plan = planner.reconcile(desired: desired, existing: original);
    expect(plan.keep.map((task) => task.offsetMinutes), [1]);
    expect(plan.replace.map((task) => task.offsetMinutes), [3]);
    expect(plan.cancel.map((task) => task.offsetMinutes), [8]);
  });

  test('arbitrary IDs are encoded and invalid tasks fail validation', () {
    final date = LocalDate(2026, 10, 5);
    final start = DateTime(2026, 10, 5, 9);
    final task = ClassSampleTask(
      slotId: 'slot:one/two',
      date: date,
      offsetMinutes: 1,
      classStart: start,
      runAt: start.add(const Duration(minutes: 1)),
    );
    expect(task.uniqueName, contains('slot%3Aone%2Ftwo'));
    expect(
      () => ClassSampleTask(
        slotId: '',
        date: date,
        offsetMinutes: 1,
        classStart: start,
        runAt: start,
      ),
      throwsArgumentError,
    );
    expect(
      () => ClassSampleTask(
        slotId: 'slot',
        date: date,
        offsetMinutes: 0,
        classStart: start,
        runAt: start,
      ),
      throwsArgumentError,
    );
  });
}
