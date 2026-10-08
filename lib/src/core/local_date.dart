import 'package:did_i_attend/src/core/local_time.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

@immutable
final class LocalDate extends Equatable implements Comparable<LocalDate> {
  LocalDate(this.year, this.month, this.day) {
    if (year < 1 || year > 9999) {
      throw RangeError.range(year, 1, 9999, 'year');
    }
    final normalized = DateTime.utc(year, month, day);
    if (normalized.year != year ||
        normalized.month != month ||
        normalized.day != day) {
      throw ArgumentError('Invalid calendar date.');
    }
  }

  factory LocalDate.fromDateTime(DateTime instant) {
    final local = instant.toLocal();
    return LocalDate(local.year, local.month, local.day);
  }

  final int year;
  final int month;
  final int day;

  int get weekday => DateTime.utc(year, month, day).weekday;

  DateTime at(LocalTime time) =>
      DateTime(year, month, day, time.hour, time.minute);

  LocalDate addDays(int days) {
    final date = DateTime.utc(year, month, day + days);
    return LocalDate(date.year, date.month, date.day);
  }

  @override
  int compareTo(LocalDate other) {
    final yearOrder = year.compareTo(other.year);
    if (yearOrder != 0) return yearOrder;
    final monthOrder = month.compareTo(other.month);
    return monthOrder != 0 ? monthOrder : day.compareTo(other.day);
  }

  @override
  List<Object> get props => [year, month, day];
}
