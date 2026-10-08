import 'package:did_i_attend/src/core/local_date.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  test('defaults to an unbounded semester', () {
    final course = sampleCourse();
    expect(course.activeFrom, isNull);
    expect(course.activeUntil, isNull);
    expect(course.isActiveOn(LocalDate(2026, 1, 1)), isTrue);
  });

  test('semester bounds are inclusive, ordered, and may be one-sided', () {
    final from = LocalDate(2026, 10, 5);
    final until = LocalDate(2026, 12, 31);
    final course = sampleCourse().copyWith(
      activeFrom: () => from,
      activeUntil: () => until,
    );
    expect(course.isActiveOn(from), isTrue);
    expect(course.isActiveOn(until), isTrue);
    expect(course.isActiveOn(from.addDays(-1)), isFalse);
    expect(course.isActiveOn(until.addDays(1)), isFalse);
    expect(
      sampleCourse().copyWith(activeFrom: () => from).isActiveOn(from),
      isTrue,
    );
    expect(
      sampleCourse().copyWith(activeUntil: () => until).isActiveOn(until),
      isTrue,
    );
    expect(
      () => course.copyWith(activeUntil: () => from.addDays(-1)),
      throwsArgumentError,
    );
    expect(course.copyWith(activeUntil: () => from).isActiveOn(from), isTrue);
  });

  test('has value equality and can copy, replace and clear optional dates', () {
    final course = sampleCourse();
    expectValueEquality(course, sampleCourse(), [
      course.copyWith(id: recordId),
      course.copyWith(name: 'Physics'),
      course.copyWith(activeFrom: () => LocalDate(2026, 10, 5)),
      course.copyWith(activeUntil: () => LocalDate(2026, 12, 31)),
    ]);
    expect(course.copyWith(), course);
    final bounded = course.copyWith(activeFrom: () => LocalDate(2026, 10, 5));
    expect(bounded.copyWith().activeFrom, bounded.activeFrom);
    expect(bounded.copyWith(activeFrom: () => null), course);
  });

  test('rejects blank IDs and names', () {
    expect(() => sampleCourse().copyWith(id: ' '), throwsArgumentError);
    expect(() => sampleCourse().copyWith(name: ''), throwsArgumentError);
  });
}
