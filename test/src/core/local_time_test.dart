import 'package:did_i_attend/src/core/local_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('converts every valid minute to a local time and back', () {
    for (var minute = 0; minute < 1440; minute++) {
      final time = LocalTime.fromMinutesSinceMidnight(minute);
      expect(time.minutesSinceMidnight, minute);
      expect(time.hour, minute ~/ 60);
      expect(time.minute, minute % 60);
    }
  });

  test('has value equality and chronological ordering', () {
    final time = LocalTime(hour: 9, minute: 15);
    final equal = LocalTime.fromMinutesSinceMidnight(555);
    expect(time, equal);
    expect(time.hashCode, equal.hashCode);
    expect(time.compareTo(LocalTime(hour: 10, minute: 0)), isNegative);
    expect(time.compareTo(equal), 0);
    expect(time.compareTo(LocalTime(hour: 9, minute: 14)), isPositive);
  });

  test('rejects invalid hours, minutes and minutes since midnight', () {
    for (final hour in [-1, 24]) {
      expect(() => LocalTime(hour: hour, minute: 0), throwsRangeError);
    }
    for (final minute in [-1, 60]) {
      expect(() => LocalTime(hour: 0, minute: minute), throwsRangeError);
    }
    for (final minute in [-1, 1440]) {
      expect(
        () => LocalTime.fromMinutesSinceMidnight(minute),
        throwsRangeError,
      );
    }
  });
}
