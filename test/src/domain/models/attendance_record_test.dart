import 'package:did_i_attend/src/core/local_date.dart';
import 'package:did_i_attend/src/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  test('has value equality and copyWith changes each field', () {
    final record = sampleAttendance();
    expectValueEquality(record, sampleAttendance(), [
      record.copyWith(id: placeId),
      record.copyWith(slotId: recordId),
      record.copyWith(courseId: recordId),
      record.copyWith(occurrenceDate: LocalDate(2026, 10, 6)),
      record.copyWith(status: AttendanceStatus.late),
      record.copyWith(source: AttendanceSource.manual),
      record.copyWith(checkInAt: () => DateTime.utc(2026, 10, 5, 9, 5)),
      record.copyWith(evaluatedAt: DateTime.utc(2026, 10, 5, 12)),
    ]);
    expect(record.copyWith(), record);
    expect(record.copyWith(checkInAt: () => null).checkInAt, isNull);
    expect(record.checkInAt, isNotNull);
  });

  test('normalizes timestamps while retaining the local occurrence date', () {
    final checkIn = DateTime(2026, 10, 5, 9);
    final evaluated = DateTime(2026, 10, 5, 11);
    final record = sampleAttendance().copyWith(
      checkInAt: () => checkIn,
      evaluatedAt: evaluated,
    );
    expect(record.checkInAt, checkIn.toUtc());
    expect(record.checkInAt!.isUtc, isTrue);
    expect(record.evaluatedAt, evaluated.toUtc());
    expect(record.evaluatedAt.isUtc, isTrue);
    expect(record.occurrenceDate, LocalDate(2026, 10, 5));
  });

  test('check-in may equal evaluation but cannot follow it', () {
    final record = sampleAttendance();
    expect(
      record.copyWith(checkInAt: () => record.evaluatedAt).checkInAt,
      record.evaluatedAt,
    );
    expect(
      () => record.copyWith(
        checkInAt: () => record.evaluatedAt.add(const Duration(seconds: 1)),
      ),
      throwsArgumentError,
    );
  });

  test('rejects blank identifiers', () {
    expect(() => sampleAttendance().copyWith(id: ''), throwsArgumentError);
    expect(() => sampleAttendance().copyWith(slotId: ''), throwsArgumentError);
    expect(
      () => sampleAttendance().copyWith(courseId: ''),
      throwsArgumentError,
    );
  });
}
