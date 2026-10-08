import 'package:did_i_attend/src/core/local_date.dart';
import 'package:did_i_attend/src/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  test('derives local start, end and date with value equality', () {
    final occurrence = sampleOccurrence();
    expect(occurrence, sampleOccurrence());
    expect(occurrence.hashCode, sampleOccurrence().hashCode);
    expect(occurrence.start, DateTime(2026, 10, 5, 9));
    expect(occurrence.end, DateTime(2026, 10, 5, 10, 30));
    expect(occurrence.start.isUtc, isFalse);
    expect(occurrence.end.isUtc, isFalse);
    expect(occurrence.occurrenceDate, LocalDate(2026, 10, 5));
    final changed = ClassOccurrence(
      slot: occurrence.slot,
      course: occurrence.course,
      place: occurrence.place,
      start: occurrence.start,
      end: DateTime(2026, 10, 5, 11),
    );
    expect(changed, isNot(occurrence));
  });

  test('constructs overnight classes using the next local calendar day', () {
    final occurrence = ClassOccurrence.forDate(
      slot: sampleSlot().copyWith(startMinute: 1410, durationMinutes: 90),
      course: sampleCourse(),
      place: samplePlace(),
      date: LocalDate(2026, 10, 5),
    );
    expect(occurrence.start, DateTime(2026, 10, 5, 23, 30));
    expect(occurrence.end, DateTime(2026, 10, 6, 1));
    expect(occurrence.occurrenceDate, LocalDate(2026, 10, 5));
  });

  test('rejects mismatched entity references', () {
    final occurrence = sampleOccurrence();
    expect(
      () => ClassOccurrence(
        slot: occurrence.slot.copyWith(courseId: recordId),
        course: occurrence.course,
        place: occurrence.place,
        start: occurrence.start,
        end: occurrence.end,
      ),
      throwsArgumentError,
    );
    expect(
      () => ClassOccurrence(
        slot: occurrence.slot.copyWith(placeId: homeId),
        course: occurrence.course,
        place: occurrence.place,
        start: occurrence.start,
        end: occurrence.end,
      ),
      throwsArgumentError,
    );
  });

  test('rejects nonpositive duration and UTC wall-clock endpoints', () {
    final occurrence = sampleOccurrence();
    for (final end in [
      occurrence.start,
      occurrence.start.subtract(const Duration(minutes: 1)),
      occurrence.end.toUtc(),
    ]) {
      expect(
        () => ClassOccurrence(
          slot: occurrence.slot,
          course: occurrence.course,
          place: occurrence.place,
          start: occurrence.start,
          end: end,
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => ClassOccurrence(
        slot: occurrence.slot,
        course: occurrence.course,
        place: occurrence.place,
        start: occurrence.start.toUtc(),
        end: occurrence.end,
      ),
      throwsArgumentError,
    );
  });

  test('rejects dates outside the semester or on another weekday', () {
    expect(
      () => ClassOccurrence.forDate(
        slot: sampleSlot(),
        course: sampleCourse(),
        place: samplePlace(),
        date: LocalDate(2026, 10, 6),
      ),
      throwsArgumentError,
    );
    expect(
      () => ClassOccurrence.forDate(
        slot: sampleSlot(),
        course: sampleCourse().copyWith(
          activeFrom: () => LocalDate(2026, 10, 12),
        ),
        place: samplePlace(),
        date: LocalDate(2026, 10, 5),
      ),
      throwsArgumentError,
    );
  });
}
