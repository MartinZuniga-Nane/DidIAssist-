import 'package:clock/clock.dart';
import 'package:did_i_attend/src/core/local_date.dart';
import 'package:did_i_attend/src/domain/repositories/class_sample_schedule_store.dart';
import 'package:did_i_attend/src/domain/repositories/class_sample_task_gateway.dart';
import 'package:did_i_attend/src/domain/repositories/course_repository.dart';
import 'package:did_i_attend/src/domain/repositories/place_repository.dart';
import 'package:did_i_attend/src/domain/repositories/settings_repository.dart';
import 'package:did_i_attend/src/domain/services/class_sample_planner.dart';
import 'package:did_i_attend/src/domain/services/schedule_resolver.dart';

final class ClassSampleScheduler {
  const ClassSampleScheduler({
    required CourseRepository courses,
    required PlaceRepository places,
    required SettingsRepository settings,
    required ClassSampleScheduleStore store,
    required ClassSampleTaskGateway gateway,
    required Clock timeSource,
    ScheduleResolver resolver = const ScheduleResolver(),
    ClassSamplePlanner planner = const ClassSamplePlanner(),
  }) : _courses = courses,
       _places = places,
       _settings = settings,
       _store = store,
       _gateway = gateway,
       _clock = timeSource,
       _resolver = resolver,
       _planner = planner;

  final CourseRepository _courses;
  final PlaceRepository _places;
  final SettingsRepository _settings;
  final ClassSampleScheduleStore _store;
  final ClassSampleTaskGateway _gateway;
  final Clock _clock;
  final ScheduleResolver _resolver;
  final ClassSamplePlanner _planner;

  Future<ClassSamplePlan> sync() => _store.synchronized(() async {
    final now = _clock.now();
    final courses = await _courses.getAll();
    final slots = await _courses.getSlots();
    final places = await _places.getAll();
    final policy = (await _settings.load()).attendancePolicy;
    final longest = slots.fold<int>(
      0,
      (length, slot) =>
          slot.durationMinutes > length ? slot.durationMinutes : length,
    );
    final first = LocalDate.fromDateTime(now).addDays(-(longest ~/ 1440 + 1));
    final occurrences = _resolver.occurrencesBetween(
      from: DateTime(first.year, first.month, first.day),
      until: now.add(const Duration(hours: 24)),
      courses: courses,
      slots: slots,
      places: places,
    );
    final plan = _planner.reconcile(
      desired: _planner.tasks(
        occurrences: occurrences,
        policy: policy,
        now: now,
      ),
      existing: await _store.load(),
    );
    // A failed plugin operation rolls back the ledger. Deterministic task names
    // make retrying partially applied native registrations safe.
    for (final task in plan.cancel) {
      await _gateway.cancel(task.uniqueName);
      await _store.delete(task.uniqueName);
    }
    for (final task in plan.replace) {
      await _gateway.schedule(task, ClassSampleSchedulePolicy.replace);
      await _store.save(task);
    }
    for (final task in plan.keep) {
      await _gateway.schedule(task, ClassSampleSchedulePolicy.keep);
    }
    return plan;
  });
}
