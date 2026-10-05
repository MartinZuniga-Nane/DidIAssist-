import 'package:did_i_assist/src/core/local_date.dart';
import 'package:did_i_assist/src/domain/models/attendance_source.dart';
import 'package:did_i_assist/src/domain/models/attendance_status.dart';
import 'package:did_i_assist/src/domain/models/model_validation.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

@immutable
final class AttendanceRecord extends Equatable {
  AttendanceRecord({
    required this.id,
    required this.slotId,
    required this.courseId,
    required this.occurrenceDate,
    required this.status,
    required this.source,
    required DateTime evaluatedAt,
    DateTime? checkInAt,
  }) : evaluatedAt = evaluatedAt.toUtc(),
       checkInAt = checkInAt?.toUtc() {
    requireNonBlank(id, 'id');
    requireNonBlank(slotId, 'slotId');
    requireNonBlank(courseId, 'courseId');
    if (this.checkInAt != null && this.checkInAt!.isAfter(this.evaluatedAt)) {
      throw ArgumentError('checkInAt must not follow evaluatedAt.');
    }
  }

  final String id;
  final String slotId;
  final String courseId;
  final LocalDate occurrenceDate;
  final AttendanceStatus status;
  final AttendanceSource source;
  final DateTime? checkInAt;
  final DateTime evaluatedAt;

  AttendanceRecord copyWith({
    String? id,
    String? slotId,
    String? courseId,
    LocalDate? occurrenceDate,
    AttendanceStatus? status,
    AttendanceSource? source,
    DateTime? Function()? checkInAt,
    DateTime? evaluatedAt,
  }) => AttendanceRecord(
    id: id ?? this.id,
    slotId: slotId ?? this.slotId,
    courseId: courseId ?? this.courseId,
    occurrenceDate: occurrenceDate ?? this.occurrenceDate,
    status: status ?? this.status,
    source: source ?? this.source,
    checkInAt: checkInAt == null ? this.checkInAt : checkInAt(),
    evaluatedAt: evaluatedAt ?? this.evaluatedAt,
  );

  @override
  List<Object?> get props => [
    id,
    slotId,
    courseId,
    occurrenceDate,
    status,
    source,
    checkInAt,
    evaluatedAt,
  ];
}
