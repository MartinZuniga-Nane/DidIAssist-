import 'dart:math' as math;

import 'package:did_i_attend/src/core/local_date.dart';
import 'package:did_i_attend/src/domain/models/models.dart';
import 'package:equatable/equatable.dart';

String _dateText(LocalDate date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

final class ClassSampleTask extends Equatable {
  ClassSampleTask({
    required this.slotId,
    required this.date,
    required this.offsetMinutes,
    required DateTime classStart,
    required DateTime runAt,
  }) : classStart = classStart.toUtc(),
       runAt = runAt.toUtc() {
    if (slotId.trim().isEmpty || offsetMinutes <= 0) {
      throw ArgumentError(
        'Sample tasks require a slot ID and positive offset.',
      );
    }
  }

  final String slotId;
  final LocalDate date;
  final int offsetMinutes;
  final DateTime classStart;
  final DateTime runAt;

  String get uniqueName =>
      'did_i_attend.class_sample.${Uri.encodeComponent(slotId)}.'
      '${_dateText(date)}.$offsetMinutes';

  @override
  List<Object> get props => [slotId, date, offsetMinutes, classStart, runAt];
}

enum ClassSampleSchedulePolicy { keep, replace }

final class ClassSamplePlan {
  ClassSamplePlan({
    required Iterable<ClassSampleTask> keep,
    required Iterable<ClassSampleTask> replace,
    required Iterable<ClassSampleTask> cancel,
  }) : keep = List.unmodifiable(keep),
       replace = List.unmodifiable(replace),
       cancel = List.unmodifiable(cancel);

  final List<ClassSampleTask> keep;
  final List<ClassSampleTask> replace;
  final List<ClassSampleTask> cancel;
}

final class ClassSamplePlanner {
  const ClassSamplePlanner();

  List<ClassSampleTask> tasks({
    required Iterable<ClassOccurrence> occurrences,
    required AttendancePolicy policy,
    required DateTime now,
  }) {
    final until = now.add(const Duration(hours: 24));
    final tasks = <String, ClassSampleTask>{};
    for (final occurrence in occurrences) {
      if (!occurrence.start.isBefore(until) || occurrence.end.isBefore(now)) {
        continue;
      }
      final date = occurrence.occurrenceDate;
      for (final offset in {1, math.max(policy.graceMinutes - 2, 2)}) {
        // Construct wall-clock offsets locally, including DST and midnight.
        final runAt = DateTime(
          date.year,
          date.month,
          date.day,
          0,
          occurrence.slot.startMinute + offset,
        );
        if (runAt.isBefore(now)) continue;
        final task = ClassSampleTask(
          slotId: occurrence.slot.id,
          date: date,
          offsetMinutes: offset,
          classStart: occurrence.start,
          runAt: runAt,
        );
        tasks[task.uniqueName] = task;
      }
    }
    return List.unmodifiable(tasks.values.toList()..sort(_compareTasks));
  }

  ClassSamplePlan reconcile({
    required Iterable<ClassSampleTask> desired,
    required Iterable<ClassSampleTask> existing,
  }) {
    final old = {for (final task in existing) task.uniqueName: task};
    final next = {for (final task in desired) task.uniqueName: task};
    return ClassSamplePlan(
      keep: next.values.where((task) => old[task.uniqueName] == task),
      replace: next.values.where((task) => old[task.uniqueName] != task),
      cancel: old.values.where((task) => !next.containsKey(task.uniqueName)),
    );
  }
}

int _compareTasks(ClassSampleTask a, ClassSampleTask b) {
  final timeOrder = a.runAt.compareTo(b.runAt);
  return timeOrder != 0 ? timeOrder : a.uniqueName.compareTo(b.uniqueName);
}
