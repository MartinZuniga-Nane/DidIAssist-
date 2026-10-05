import 'package:did_i_assist/src/core/local_date.dart';
import 'package:did_i_assist/src/core/local_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts leap days and rejects normalized or out-of-range dates', () {
    expect(LocalDate(2024, 2, 29).day, 29);
    for (final parts in [
      [2025, 2, 29],
      [2026, 0, 1],
      [2026, 13, 1],
      [2026, 4, 31],
      [2026, 1, 0],
      [0, 1, 1],
      [10000, 1, 1],
    ]) {
      expect(
        () => LocalDate(parts[0], parts[1], parts[2]),
        throwsArgumentError,
      );
    }
  });

  test('has value equality and calendar ordering', () {
    final date = LocalDate(2026, 10, 5);
    final equal = LocalDate(2026, 10, 5);
    expect(date, equal);
    expect(date.hashCode, equal.hashCode);
    expect(date.weekday, DateTime.monday);
    expect(date.compareTo(equal), 0);
    expect(date.compareTo(LocalDate(2027, 1, 1)), isNegative);
    expect(date.compareTo(LocalDate(2026, 11, 1)), isNegative);
    expect(date.compareTo(LocalDate(2026, 10, 4)), isPositive);
  });

  test('calendar-day arithmetic handles month, year and leap boundaries', () {
    expect(LocalDate(2026, 12, 31).addDays(1), LocalDate(2027, 1, 1));
    expect(LocalDate(2024, 3, 1).addDays(-1), LocalDate(2024, 2, 29));
    expect(LocalDate(2026, 10, 5).addDays(0), LocalDate(2026, 10, 5));
  });

  test('constructs a local wall-clock time', () {
    final date = LocalDate(2026, 10, 5);
    final instant = date.at(LocalTime(hour: 9, minute: 30));
    expect(instant, DateTime(2026, 10, 5, 9, 30));
    expect(instant.isUtc, isFalse);
    expect(LocalDate.fromDateTime(instant), date);
  });

  test('converts an instant to its local date before extracting fields', () {
    final instant = DateTime.utc(2026, 10, 5, 1);
    final local = instant.toLocal();
    expect(
      LocalDate.fromDateTime(instant),
      LocalDate(local.year, local.month, local.day),
    );
  });
}
