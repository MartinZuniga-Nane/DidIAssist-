import 'package:did_i_attend/src/core/local_date.dart';
import 'package:did_i_attend/src/domain/models/models.dart';
import 'package:did_i_attend/src/domain/models/planned_notification.dart';
import 'package:did_i_attend/src/platform/notifications/notification_message.dart';
import 'package:did_i_attend/src/platform/notifications/notification_message_builder.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final checkIn = DateTime.utc(2026, 10, 5, 9, 5);
  for (final language in ['en', 'es']) {
    group(language, () {
      late NotificationMessageBuilder builder;
      final spanish = language == 'es';
      final time = spanish ? '9:05' : '9:05\u202fAM';

      setUp(() async {
        builder = await NotificationMessageBuilder.create(
          Locale(language),
          localizeInstant: (instant) => instant.toUtc(),
        );
      });

      for (final minutes in [1, 25]) {
        test(
          'departure includes course, place, time and $minutes minutes',
          () {
            final message = builder.build(
              PlannedNotification(
                id: 1,
                kind: NotificationKind.departureReminder,
                at: checkIn,
                payload: {
                  'courseName': 'Mathematics',
                  'placeName': 'Campus',
                  'etaMinutes': '$minutes',
                },
              ),
            );
            expect(
              message.title,
              spanish
                  ? 'Hora de salir para Mathematics'
                  : 'Time to leave for Mathematics',
            );
            final duration = spanish
                ? '$minutes ${minutes == 1 ? 'minuto' : 'minutos'}'
                : '$minutes ${minutes == 1 ? 'minute' : 'minutes'}';
            expect(
              message.body,
              spanish
                  ? 'Sal a más tardar a las $time para Mathematics en Campus. '
                        'Tiempo de viaje: $duration.'
                  : 'Leave by $time for Mathematics at Campus. '
                        'Travel time: $duration.',
            );
          },
        );
      }

      for (final status in [
        AttendanceStatus.present,
        AttendanceStatus.late,
        AttendanceStatus.absent,
      ]) {
        test(
          'renders ${status.name} from records and plans',
          () {
            final record = AttendanceRecord(
              id: 'record',
              slotId: 'slot',
              courseId: 'course',
              occurrenceDate: LocalDate(2026, 10, 5),
              status: status,
              source: AttendanceSource.automatic,
              evaluatedAt: checkIn.add(const Duration(hours: 1)),
              checkInAt: status == AttendanceStatus.absent ? null : checkIn,
            );
            final message = builder.forRecord(
              record,
              courseName: 'Mathematics',
            );
            final planned = builder.build(
              PlannedNotification(
                id: 2,
                kind: NotificationKind.attendanceResult,
                at: record.evaluatedAt,
                payload: {
                  'courseName': 'Mathematics',
                  'status': status.name,
                  if (record.checkInAt != null)
                    'checkInAt': checkIn.toIso8601String(),
                },
              ),
            );
            expect(planned, message);
            if (status == AttendanceStatus.absent) {
              expect(
                message.title,
                spanish ? 'Inasistencia registrada' : 'Absence recorded',
              );
              expect(
                message.body,
                spanish
                    ? 'Se registró tu inasistencia a Mathematics.'
                    : 'You were marked absent for Mathematics.',
              );
            } else {
              expect(
                message.title,
                spanish ? 'Asistencia registrada' : 'Attendance recorded',
              );
              final statusText = status == AttendanceStatus.present
                  ? (spanish ? 'presente' : 'present')
                  : (spanish ? 'llegada tarde' : 'late');
              expect(
                message.body,
                spanish
                    ? 'Mathematics: $statusText. '
                          'Llegada registrada a las $time.'
                    : 'Mathematics: $statusText. Checked in at $time.',
              );
            }
          },
        );
      }

      test('missing course and check-in time use translated fallbacks', () {
        final message = builder.build(
          PlannedNotification(
            id: 3,
            kind: NotificationKind.attendanceResult,
            at: checkIn,
            payload: const {'status': 'present'},
          ),
        );
        expect(message.body, spanish ? 'Clase: presente.' : 'Class: present.');
        final late = builder.build(
          PlannedNotification(
            id: 3,
            kind: NotificationKind.attendanceResult,
            at: checkIn,
            payload: const {'status': 'late'},
          ),
        );
        expect(late.body, spanish ? 'Clase: llegada tarde.' : 'Class: late.');
      });

      for (final minutes in [1, 7]) {
        test('late warning pluralizes $minutes minutes', () {
          final message = builder.lateWarning(
            courseName: 'Mathematics',
            lateMinutes: minutes,
          );
          final duration = spanish
              ? '$minutes ${minutes == 1 ? 'minuto' : 'minutos'}'
              : '$minutes ${minutes == 1 ? 'minute' : 'minutes'}';
          expect(
            message.title,
            spanish
                ? 'Vas tarde a Mathematics'
                : 'Running late for Mathematics',
          );
          expect(
            message.body,
            spanish
                ? 'Llegarás $duration tarde a Mathematics.'
                : 'You will arrive $duration late to Mathematics.',
          );
        });
      }

      test('channel strings are localized', () {
        expect(
          builder.strings.departureChannelName,
          spanish ? 'Recordatorios de salida' : 'Departure reminders',
        );
        expect(
          builder.strings.attendanceChannelName,
          spanish ? 'Resultados de asistencia' : 'Attendance results',
        );
        expect(builder.strings.departureChannelDescription, isNotEmpty);
        expect(builder.strings.attendanceChannelDescription, isNotEmpty);
      });

      test(
        'unsupported attendance states and negative lateness are rejected',
        () {
          for (final status in [
            AttendanceStatus.pending,
            AttendanceStatus.excused,
          ]) {
            expect(
              () => builder.build(
                PlannedNotification(
                  id: 1,
                  kind: NotificationKind.attendanceResult,
                  at: checkIn,
                  payload: {'status': status.name},
                ),
              ),
              throwsArgumentError,
            );
          }
          expect(
            () => builder.lateWarning(courseName: 'Class', lateMinutes: -1),
            throwsRangeError,
          );
        },
      );
    });
  }

  test(
    'unsupported locale falls back to English; regional Spanish works',
    () async {
      final fallback = await NotificationMessageBuilder.create(
        const Locale('fr'),
      );
      final spanish = await NotificationMessageBuilder.create(
        const Locale('es', 'CL'),
      );
      expect(fallback.strings.localeName, 'en');
      expect(spanish.strings.localeName, 'es');
    },
  );

  test(
    'injected local timezone determines the displayed wall-clock time',
    () async {
      final builder = await NotificationMessageBuilder.create(
        const Locale('es'),
        localizeInstant: (instant) =>
            instant.toUtc().subtract(const Duration(hours: 3)),
      );
      expect(
        builder
            .build(
              PlannedNotification(
                id: 1,
                kind: NotificationKind.attendanceResult,
                at: checkIn,
                payload: {
                  'status': 'late',
                  'courseName': 'Class',
                  'checkInAt': checkIn.toIso8601String(),
                },
              ),
            )
            .body,
        'Class: llegada tarde. Llegada registrada a las 6:05.',
      );
    },
  );

  test('messages have value equality', () {
    expect(
      const NotificationMessage(title: 'Title', body: 'Body'),
      const NotificationMessage(title: 'Title', body: 'Body'),
    );
  });
}
