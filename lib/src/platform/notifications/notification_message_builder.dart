import 'package:did_i_assist/src/domain/models/attendance_record.dart';
import 'package:did_i_assist/src/domain/models/attendance_status.dart';
import 'package:did_i_assist/src/domain/models/planned_notification.dart';
import 'package:did_i_assist/src/l10n/generated/app_localizations.dart';
import 'package:did_i_assist/src/platform/notifications/notification_message.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

final class NotificationMessageBuilder {
  NotificationMessageBuilder._(this.strings, this._localizeInstant);

  static Future<NotificationMessageBuilder> create(
    Locale locale, {
    DateTime Function(DateTime)? localizeInstant,
  }) async {
    final language = locale.languageCode == 'es' ? 'es' : 'en';
    final strings = lookupAppLocalizations(Locale(language));
    await initializeDateFormatting(strings.localeName);
    return NotificationMessageBuilder._(
      strings,
      localizeInstant ?? (instant) => instant.toLocal(),
    );
  }

  final AppLocalizations strings;
  final DateTime Function(DateTime) _localizeInstant;

  String _time(DateTime instant) =>
      DateFormat.jm(strings.localeName).format(_localizeInstant(instant));

  NotificationMessage build(PlannedNotification notification) {
    final payload = notification.payload;
    switch (notification.kind) {
      case NotificationKind.departureReminder:
        final courseName = payload['courseName']!;
        final eta = int.parse(payload['etaMinutes']!);
        return NotificationMessage(
          title: strings.departureReminderTitle(courseName),
          body: strings.departureReminderBody(
            courseName,
            payload['placeName']!,
            _time(notification.at),
            eta,
          ),
        );
      case NotificationKind.attendanceResult:
        return _attendance(
          status: AttendanceStatus.values.byName(payload['status']!),
          courseName: payload['courseName'],
          checkInAt: payload['checkInAt'] == null
              ? null
              : DateTime.parse(payload['checkInAt']!),
        );
    }
  }

  NotificationMessage forRecord(
    AttendanceRecord record, {
    String? courseName,
  }) => _attendance(
    status: record.status,
    courseName: courseName,
    checkInAt: record.checkInAt,
  );

  NotificationMessage _attendance({
    required AttendanceStatus status,
    required String? courseName,
    required DateTime? checkInAt,
  }) {
    final name = courseName ?? strings.unknownCourseName;
    final time = checkInAt == null ? null : _time(checkInAt);
    final body = switch (status) {
      AttendanceStatus.present =>
        time == null
            ? strings.attendancePresentWithoutTimeBody(name)
            : strings.attendancePresentBody(name, time),
      AttendanceStatus.late =>
        time == null
            ? strings.attendanceLateWithoutTimeBody(name)
            : strings.attendanceLateBody(name, time),
      AttendanceStatus.absent => strings.attendanceAbsentBody(name),
      _ => throw ArgumentError.value(status, 'status', 'Not notifiable.'),
    };
    return NotificationMessage(
      title: status == AttendanceStatus.absent
          ? strings.attendanceAbsentTitle
          : strings.attendanceRecordedTitle,
      body: body,
    );
  }

  NotificationMessage lateWarning({
    required String courseName,
    required int lateMinutes,
  }) {
    if (lateMinutes < 0) {
      throw RangeError.value(
        lateMinutes,
        'lateMinutes',
        'Must be nonnegative.',
      );
    }
    return NotificationMessage(
      title: strings.lateWarningTitle(courseName),
      body: strings.lateWarningBody(courseName, lateMinutes),
    );
  }
}
