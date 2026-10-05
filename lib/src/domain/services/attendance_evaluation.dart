import 'package:did_i_assist/src/domain/models/attendance_status.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

@immutable
final class AttendanceEvaluation extends Equatable {
  AttendanceEvaluation({required this.status, DateTime? checkInAt})
    : checkInAt = checkInAt?.toUtc() {
    if (status == AttendanceStatus.excused) {
      throw ArgumentError('Automatic evaluations cannot excuse attendance.');
    }
    if (status == AttendanceStatus.pending && checkInAt != null) {
      throw ArgumentError('Pending evaluations cannot have a check-in.');
    }
    if ((status == AttendanceStatus.present ||
            status == AttendanceStatus.late) &&
        checkInAt == null) {
      throw ArgumentError('Present and late evaluations require a check-in.');
    }
  }

  final AttendanceStatus status;

  /// First inside evidence, including arrivals too late to count as attendance.
  final DateTime? checkInAt;

  @override
  List<Object?> get props => [status, checkInAt];
}
