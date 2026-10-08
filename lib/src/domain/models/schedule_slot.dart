import 'package:did_i_attend/src/domain/models/model_validation.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

@immutable
final class ScheduleSlot extends Equatable {
  ScheduleSlot({
    required this.id,
    required this.courseId,
    required this.placeId,
    required this.weekday,
    required this.startMinute,
    required this.durationMinutes,
  }) {
    requireNonBlank(id, 'id');
    requireNonBlank(courseId, 'courseId');
    requireNonBlank(placeId, 'placeId');
    if (weekday < 1 || weekday > 7) {
      throw RangeError.range(weekday, 1, 7, 'weekday');
    }
    if (startMinute < 0 || startMinute > 1439) {
      throw RangeError.range(startMinute, 0, 1439, 'startMinute');
    }
    if (durationMinutes <= 0) {
      throw ArgumentError.value(
        durationMinutes,
        'durationMinutes',
        'Must be positive.',
      );
    }
  }

  final String id;
  final String courseId;
  final String placeId;
  final int weekday;
  final int startMinute;
  final int durationMinutes;

  ScheduleSlot copyWith({
    String? id,
    String? courseId,
    String? placeId,
    int? weekday,
    int? startMinute,
    int? durationMinutes,
  }) => ScheduleSlot(
    id: id ?? this.id,
    courseId: courseId ?? this.courseId,
    placeId: placeId ?? this.placeId,
    weekday: weekday ?? this.weekday,
    startMinute: startMinute ?? this.startMinute,
    durationMinutes: durationMinutes ?? this.durationMinutes,
  );

  @override
  List<Object> get props => [
    id,
    courseId,
    placeId,
    weekday,
    startMinute,
    durationMinutes,
  ];
}
