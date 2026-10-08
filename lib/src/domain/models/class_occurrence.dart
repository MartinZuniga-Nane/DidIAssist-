import 'package:did_i_attend/src/core/local_date.dart';
import 'package:did_i_attend/src/domain/models/course.dart';
import 'package:did_i_attend/src/domain/models/place.dart';
import 'package:did_i_attend/src/domain/models/schedule_slot.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

@immutable
final class ClassOccurrence extends Equatable {
  ClassOccurrence({
    required this.slot,
    required this.course,
    required this.place,
    required this.start,
    required this.end,
  }) {
    if (slot.courseId != course.id || slot.placeId != place.id) {
      throw ArgumentError(
        'The slot must reference the supplied course and place.',
      );
    }
    if (start.isUtc || end.isUtc) {
      throw ArgumentError('Class times must use local wall-clock DateTimes.');
    }
    if (!end.isAfter(start)) {
      throw ArgumentError('end must follow start.');
    }
  }

  factory ClassOccurrence.forDate({
    required ScheduleSlot slot,
    required Course course,
    required Place place,
    required LocalDate date,
  }) {
    if (date.weekday != slot.weekday || !course.isActiveOn(date)) {
      throw ArgumentError('The course and slot are not active on this date.');
    }
    // Construct both wall-clock endpoints locally, including overnight classes.
    return ClassOccurrence(
      slot: slot,
      course: course,
      place: place,
      start: DateTime(date.year, date.month, date.day, 0, slot.startMinute),
      end: DateTime(
        date.year,
        date.month,
        date.day,
        0,
        slot.startMinute + slot.durationMinutes,
      ),
    );
  }

  final ScheduleSlot slot;
  final Course course;
  final Place place;
  final DateTime start;
  final DateTime end;

  LocalDate get occurrenceDate => LocalDate.fromDateTime(start);

  @override
  List<Object> get props => [slot, course, place, start, end];
}
