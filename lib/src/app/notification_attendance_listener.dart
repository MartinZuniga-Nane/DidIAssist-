import 'package:did_i_assist/src/app/background_operations.dart';
import 'package:did_i_assist/src/domain/models/attendance_record.dart';
import 'package:did_i_assist/src/domain/services/attendance_notifier.dart';

final class NotificationAttendanceListener implements AttendanceResultListener {
  const NotificationAttendanceListener(this._notifier);

  final AttendanceNotifier _notifier;

  @override
  Future<void> onAttendanceWritten(List<AttendanceRecord> records) async {
    await _notifier.notify(records);
  }
}
