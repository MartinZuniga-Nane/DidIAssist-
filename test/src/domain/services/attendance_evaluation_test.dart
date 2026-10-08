import 'package:did_i_attend/src/domain/models/attendance_status.dart';
import 'package:did_i_attend/src/domain/services/attendance_evaluation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes check-in to UTC and compares by value', () {
    final time = DateTime(2026, 10, 5, 9);
    final first = AttendanceEvaluation(
      status: AttendanceStatus.present,
      checkInAt: time,
    );
    final equal = AttendanceEvaluation(
      status: AttendanceStatus.present,
      checkInAt: time.toUtc(),
    );
    expect(first, equal);
    expect(first.hashCode, equal.hashCode);
    expect(first.checkInAt!.isUtc, isTrue);
    expect(
      first,
      isNot(
        AttendanceEvaluation(status: AttendanceStatus.late, checkInAt: time),
      ),
    );
    expect(
      first,
      isNot(
        AttendanceEvaluation(
          status: AttendanceStatus.present,
          checkInAt: time.add(const Duration(milliseconds: 1)),
        ),
      ),
    );
  });

  test('absence can retain an arrival too late to count as attendance', () {
    final time = DateTime(2026, 10, 5, 10);
    final absent = AttendanceEvaluation(
      status: AttendanceStatus.absent,
      checkInAt: time,
    );
    expect(absent.checkInAt, time.toUtc());
    expect(
      absent,
      isNot(AttendanceEvaluation(status: AttendanceStatus.absent)),
    );
  });

  test('pending and absent can have no check-in', () {
    expect(
      AttendanceEvaluation(status: AttendanceStatus.pending).checkInAt,
      isNull,
    );
    expect(
      AttendanceEvaluation(status: AttendanceStatus.absent).checkInAt,
      isNull,
    );
  });

  test('rejects excused results and inconsistent check-ins', () {
    expect(
      () => AttendanceEvaluation(status: AttendanceStatus.excused),
      throwsArgumentError,
    );
    expect(
      () => AttendanceEvaluation(
        status: AttendanceStatus.pending,
        checkInAt: DateTime(2026, 10, 5),
      ),
      throwsArgumentError,
    );
    for (final status in [AttendanceStatus.present, AttendanceStatus.late]) {
      expect(
        () => AttendanceEvaluation(status: status),
        throwsArgumentError,
      );
    }
  });
}
