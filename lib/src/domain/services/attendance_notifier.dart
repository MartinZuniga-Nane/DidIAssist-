import 'package:did_i_assist/src/domain/models/attendance_record.dart';
import 'package:did_i_assist/src/domain/models/attendance_source.dart';
import 'package:did_i_assist/src/domain/models/attendance_status.dart';
import 'package:did_i_assist/src/domain/models/planned_notification.dart';
import 'package:did_i_assist/src/domain/repositories/course_repository.dart';
import 'package:did_i_assist/src/domain/repositories/notification_gateway.dart';
import 'package:did_i_assist/src/domain/repositories/settings_repository.dart';
import 'package:did_i_assist/src/domain/services/notification_id.dart';

final class AttendanceNotifier {
  AttendanceNotifier({
    required NotificationGateway gateway,
    required SettingsRepository settingsRepository,
    required CourseRepository courseRepository,
  }) : _gateway = gateway,
       _settings = settingsRepository,
       _courses = courseRepository;

  final NotificationGateway _gateway;
  final SettingsRepository _settings;
  final CourseRepository _courses;

  /// Consumes only records actually written by AttendanceService.
  Future<List<int>> notify(Iterable<AttendanceRecord> records) async {
    if (!(await _settings.load()).notificationsEnabled) return const [];
    final eligible = records
        .where(
          (record) =>
              record.source == AttendanceSource.automatic &&
              (record.status == AttendanceStatus.present ||
                  record.status == AttendanceStatus.late ||
                  record.status == AttendanceStatus.absent),
        )
        .toList();
    if (eligible.isEmpty ||
        await _gateway.ensurePermission() != NotificationPermission.granted) {
      return const [];
    }
    final courses = {
      for (final course in await _courses.getAll()) course.id: course,
    };
    final shown = <int>{};
    for (final record in eligible) {
      final id = notificationId(
        kind: NotificationKind.attendanceResult,
        slotId: record.slotId,
        occurrenceDate: record.occurrenceDate,
      );
      if (!shown.add(id)) continue;
      await _gateway.show(
        PlannedNotification(
          id: id,
          kind: NotificationKind.attendanceResult,
          at: record.evaluatedAt,
          payload: {
            'slotId': record.slotId,
            'occurrenceDate': notificationDateKey(record.occurrenceDate),
            'status': record.status.name,
            if (courses[record.courseId] case final course?)
              'courseName': course.name,
            if (record.checkInAt case final checkIn?)
              'checkInAt': checkIn.toIso8601String(),
          },
        ),
      );
    }
    return List.unmodifiable(shown);
  }
}
