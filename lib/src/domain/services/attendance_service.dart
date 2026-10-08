import 'package:clock/clock.dart';
import 'package:did_i_attend/src/core/local_date.dart';
import 'package:did_i_attend/src/domain/models/models.dart';
import 'package:did_i_attend/src/domain/repositories/attendance_repository.dart';
import 'package:did_i_attend/src/domain/repositories/course_repository.dart';
import 'package:did_i_attend/src/domain/repositories/location_event_repository.dart';
import 'package:did_i_attend/src/domain/repositories/place_repository.dart';
import 'package:did_i_attend/src/domain/repositories/settings_repository.dart';
import 'package:did_i_attend/src/domain/services/attendance_evaluator.dart';
import 'package:did_i_attend/src/domain/services/schedule_resolver.dart';
import 'package:uuid/uuid.dart';

final class AttendanceService {
  AttendanceService({
    required CourseRepository courseRepository,
    required PlaceRepository placeRepository,
    required AttendanceRepository attendanceRepository,
    required LocationEventRepository locationEventRepository,
    required SettingsRepository settingsRepository,
    Clock? timeSource,
    String Function()? idGenerator,
    ScheduleResolver resolver = const ScheduleResolver(),
    AttendanceEvaluator? evaluator,
  }) : _courses = courseRepository,
       _places = placeRepository,
       _attendance = attendanceRepository,
       _events = locationEventRepository,
       _settings = settingsRepository,
       _clock = timeSource ?? clock,
       _idGenerator = idGenerator ?? const Uuid().v4,
       _resolver = resolver,
       _evaluator = evaluator ?? AttendanceEvaluator();

  final CourseRepository _courses;
  final PlaceRepository _places;
  final AttendanceRepository _attendance;
  final LocationEventRepository _events;
  final SettingsRepository _settings;
  final Clock _clock;
  final String Function() _idGenerator;
  final ScheduleResolver _resolver;
  final AttendanceEvaluator _evaluator;

  Future<List<AttendanceRecord>> evaluateRecent({
    Duration lookback = const Duration(hours: 48),
  }) async {
    if (lookback.isNegative) {
      throw ArgumentError.value(lookback, 'lookback', 'Must be nonnegative.');
    }
    final now = _clock.now().toUtc();
    final settings = await _settings.load();
    final courses = await _courses.getAll();
    final slots = await _courses.getSlots();
    final places = await _places.getAll();
    final occurrences = _resolver.occurrencesBetween(
      from: now.subtract(lookback),
      until: now.add(_inclusiveEpsilon),
      courses: courses,
      slots: slots,
      places: places,
    );
    final written = <AttendanceRecord>[];
    for (final occurrence in occurrences) {
      final existing = await _attendance.findBySlotAndDate(
        occurrence.slot.id,
        occurrence.occurrenceDate,
      );
      if (existing?.source == AttendanceSource.manual) continue;
      final windowStart = occurrence.start.toUtc().subtract(
        Duration(minutes: settings.attendancePolicy.earlyWindowMinutes),
      );
      final end = occurrence.end.toUtc();
      final events = await _events.query(
        from: windowStart.subtract(_evaluator.carryOver),
        until: (end.isBefore(now) ? end : now).add(_inclusiveEpsilon),
        placeId: occurrence.place.id,
      );
      final evaluation = _evaluator.evaluate(
        occurrence: occurrence,
        place: occurrence.place,
        events: events,
        policy: settings.attendancePolicy,
        now: now,
      );
      if (evaluation.status == AttendanceStatus.pending) continue;
      if (existing != null &&
          existing.status == evaluation.status &&
          existing.checkInAt == evaluation.checkInAt) {
        continue;
      }
      final candidate = AttendanceRecord(
        id: existing?.id ?? _idGenerator(),
        slotId: occurrence.slot.id,
        courseId: occurrence.course.id,
        occurrenceDate: occurrence.occurrenceDate,
        status: evaluation.status,
        source: AttendanceSource.automatic,
        checkInAt: evaluation.checkInAt,
        evaluatedAt: now,
      );
      final stored = await _attendance.upsert(candidate);
      // The repository may retain a manual edit made after our initial read.
      if (stored.source == AttendanceSource.automatic) written.add(stored);
    }
    return List.unmodifiable(written);
  }

  Future<AttendanceRecord> markManually(
    String slotId,
    LocalDate occurrenceDate,
    AttendanceStatus status,
  ) async {
    if (status == AttendanceStatus.pending) {
      throw ArgumentError.value(status, 'status', 'Cannot be marked manually.');
    }
    final now = _clock.now().toUtc();
    final slots = await _courses.getSlots();
    ScheduleSlot? slot;
    for (final candidate in slots) {
      if (candidate.id == slotId) {
        slot = candidate;
        break;
      }
    }
    if (slot == null) {
      throw ArgumentError.value(slotId, 'slotId', 'The slot does not exist.');
    }
    if (occurrenceDate.weekday != slot.weekday) {
      throw ArgumentError.value(
        occurrenceDate,
        'occurrenceDate',
        'The date must match the slot weekday.',
      );
    }
    final course = await _courses.getById(slot.courseId);
    if (course == null) {
      throw ArgumentError.value(
        slot.courseId,
        'courseId',
        'The course does not exist.',
      );
    }
    if (!course.isActiveOn(occurrenceDate)) {
      throw ArgumentError.value(
        occurrenceDate,
        'occurrenceDate',
        'The course is not active on this date.',
      );
    }
    final existing = await _attendance.findBySlotAndDate(
      slotId,
      occurrenceDate,
    );
    return _attendance.upsert(
      AttendanceRecord(
        id: existing?.id ?? _idGenerator(),
        slotId: slotId,
        courseId: slot.courseId,
        occurrenceDate: occurrenceDate,
        status: status,
        source: AttendanceSource.manual,
        checkInAt: existing?.checkInAt,
        evaluatedAt: now,
      ),
    );
  }
}

const _inclusiveEpsilon = Duration(microseconds: 1);
