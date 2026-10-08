import 'package:did_i_attend/src/core/local_date.dart';
import 'package:did_i_attend/src/domain/models/models.dart';

final class ScheduleResolver {
  const ScheduleResolver();

  List<ClassOccurrence> occurrencesBetween({
    required DateTime from,
    required DateTime until,
    required Iterable<Course> courses,
    required Iterable<ScheduleSlot> slots,
    required Iterable<Place> places,
  }) {
    if (until.isBefore(from)) {
      throw ArgumentError('until must not precede from.');
    }
    if (from.isAtSameMomentAs(until)) return const [];

    final coursesById = {for (final course in courses) course.id: course};
    final placesById = {for (final place in places) place.id: place};
    final weeklySlots = slots.toList();
    final lastDate = LocalDate.fromDateTime(until);
    final occurrences = <ClassOccurrence>[];
    var date = LocalDate.fromDateTime(from);
    while (date.compareTo(lastDate) <= 0) {
      for (final slot in weeklySlots) {
        final course = coursesById[slot.courseId];
        final place = placesById[slot.placeId];
        if (course == null ||
            place == null ||
            slot.weekday != date.weekday ||
            !course.isActiveOn(date)) {
          continue;
        }
        final occurrence = ClassOccurrence.forDate(
          slot: slot,
          course: course,
          place: place,
          date: date,
        );
        if (!occurrence.start.isBefore(from) &&
            occurrence.start.isBefore(until)) {
          occurrences.add(occurrence);
        }
      }
      if (date == lastDate) break;
      date = date.addDays(1);
    }
    return List.unmodifiable(occurrences..sort(_compareOccurrences));
  }

  /// Returns the earliest occurrence starting strictly after [after].
  ClassOccurrence? nextOccurrence({
    required DateTime after,
    required Iterable<Course> courses,
    required Iterable<ScheduleSlot> slots,
    required Iterable<Place> places,
  }) {
    final coursesById = {for (final course in courses) course.id: course};
    final placesById = {for (final place in places) place.id: place};
    final afterDate = LocalDate.fromDateTime(after);
    ClassOccurrence? next;
    for (final slot in slots) {
      final course = coursesById[slot.courseId];
      final place = placesById[slot.placeId];
      if (course == null || place == null) continue;
      var date = afterDate;
      if (course.activeFrom != null && course.activeFrom!.compareTo(date) > 0) {
        date = course.activeFrom!;
      }
      date = date.addDays((slot.weekday - date.weekday + 7) % 7);
      if (!course.isActiveOn(date)) continue;
      var occurrence = ClassOccurrence.forDate(
        slot: slot,
        course: course,
        place: place,
        date: date,
      );
      if (!occurrence.start.isAfter(after)) {
        date = date.addDays(7);
        if (!course.isActiveOn(date)) continue;
        occurrence = ClassOccurrence.forDate(
          slot: slot,
          course: course,
          place: place,
          date: date,
        );
      }
      if (next == null || _compareOccurrences(occurrence, next) < 0) {
        next = occurrence;
      }
    }
    return next;
  }

  /// Uses [start, end); overlapping classes are ordered by start, then slot ID.
  ClassOccurrence? occurrenceAt({
    required DateTime instant,
    required Iterable<Course> courses,
    required Iterable<ScheduleSlot> slots,
    required Iterable<Place> places,
  }) {
    final weeklySlots = slots.toList();
    if (weeklySlots.isEmpty) return null;
    final longestMinutes = weeklySlots.fold<int>(
      0,
      (longest, slot) =>
          slot.durationMinutes > longest ? slot.durationMinutes : longest,
    );
    // Include an extra calendar day for offset changes and overnight classes.
    final firstDate = LocalDate.fromDateTime(
      instant,
    ).addDays(-(longestMinutes ~/ 1440 + 1));
    final candidates = occurrencesBetween(
      from: DateTime(firstDate.year, firstDate.month, firstDate.day),
      until: instant.add(const Duration(microseconds: 1)),
      courses: courses,
      slots: weeklySlots,
      places: places,
    );
    for (final occurrence in candidates) {
      if (instant.isBefore(occurrence.end)) return occurrence;
    }
    return null;
  }
}

int _compareOccurrences(ClassOccurrence first, ClassOccurrence second) {
  final startOrder = first.start.compareTo(second.start);
  return startOrder != 0 ? startOrder : first.slot.id.compareTo(second.slot.id);
}
