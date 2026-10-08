import 'package:clock/clock.dart';
import 'package:did_i_attend/src/core/local_date.dart';
import 'package:did_i_attend/src/domain/repositories/course_repository.dart';
import 'package:did_i_attend/src/domain/repositories/location_event_repository.dart';
import 'package:did_i_attend/src/domain/repositories/place_repository.dart';
import 'package:did_i_attend/src/domain/repositories/settings_repository.dart';
import 'package:did_i_attend/src/domain/services/attendance_evaluator.dart';
import 'package:did_i_attend/src/domain/services/schedule_resolver.dart';

final class AttendanceSamplingPolicy {
  AttendanceSamplingPolicy({
    required CourseRepository courses,
    required PlaceRepository places,
    required LocationEventRepository events,
    required SettingsRepository settings,
    required Clock timeSource,
    ScheduleResolver resolver = const ScheduleResolver(),
    AttendanceEvaluator? evaluator,
  }) : _courses = courses,
       _places = places,
       _events = events,
       _settings = settings,
       _clock = timeSource,
       _resolver = resolver,
       _evaluator = evaluator ?? AttendanceEvaluator();

  final CourseRepository _courses;
  final PlaceRepository _places;
  final LocationEventRepository _events;
  final SettingsRepository _settings;
  final Clock _clock;
  final ScheduleResolver _resolver;
  final AttendanceEvaluator _evaluator;

  Future<bool> needsSample() async {
    final now = _clock.now().toUtc();
    final policy = (await _settings.load()).attendancePolicy;
    final courses = await _courses.getAll();
    final slots = await _courses.getSlots();
    final places = await _places.getAll();
    final longest = slots.fold<int>(
      0,
      (length, slot) =>
          slot.durationMinutes > length ? slot.durationMinutes : length,
    );
    final first = LocalDate.fromDateTime(now).addDays(-(longest ~/ 1440 + 1));
    const epsilon = Duration(microseconds: 1);
    final early = Duration(minutes: policy.earlyWindowMinutes);
    final occurrences = _resolver.occurrencesBetween(
      from: DateTime(first.year, first.month, first.day),
      until: now.add(early).add(epsilon),
      courses: courses,
      slots: slots,
      places: places,
    );
    for (final occurrence in occurrences) {
      final windowStart = occurrence.start.toUtc().subtract(early);
      if (now.isBefore(windowStart) || now.isAfter(occurrence.end.toUtc())) {
        continue;
      }
      final evidence = await _events.query(
        from: windowStart.subtract(_evaluator.carryOver),
        until: now.add(epsilon),
        placeId: occurrence.place.id,
      );
      final evaluation = _evaluator.evaluate(
        occurrence: occurrence,
        place: occurrence.place,
        events: evidence,
        policy: policy,
        now: now,
      );
      if (evaluation.checkInAt == null) return true;
    }
    return false;
  }
}
