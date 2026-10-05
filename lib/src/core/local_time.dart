import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

@immutable
final class LocalTime extends Equatable implements Comparable<LocalTime> {
  LocalTime({required this.hour, required this.minute}) {
    if (hour < 0 || hour > 23) {
      throw RangeError.range(hour, 0, 23, 'hour');
    }
    if (minute < 0 || minute > 59) {
      throw RangeError.range(minute, 0, 59, 'minute');
    }
  }

  factory LocalTime.fromMinutesSinceMidnight(int minutes) {
    if (minutes < 0 || minutes > 1439) {
      throw RangeError.range(minutes, 0, 1439, 'minutes');
    }
    return LocalTime(hour: minutes ~/ 60, minute: minutes % 60);
  }

  final int hour;
  final int minute;

  int get minutesSinceMidnight => hour * 60 + minute;

  @override
  int compareTo(LocalTime other) =>
      minutesSinceMidnight.compareTo(other.minutesSinceMidnight);

  @override
  List<Object> get props => [hour, minute];
}
