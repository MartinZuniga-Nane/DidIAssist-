import 'package:did_i_attend/src/core/local_date.dart';
import 'package:did_i_attend/src/domain/models/models.dart';
import 'package:did_i_attend/src/domain/models/planned_notification.dart';
import 'package:did_i_attend/src/domain/repositories/course_repository.dart';
import 'package:did_i_attend/src/domain/repositories/notification_gateway.dart';
import 'package:did_i_attend/src/domain/repositories/settings_repository.dart';
import 'package:did_i_attend/src/domain/services/attendance_notifier.dart';
import 'package:did_i_attend/src/domain/services/notification_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Gateway extends Mock implements NotificationGateway {}

class _Settings extends Mock implements SettingsRepository {}

class _Courses extends Mock implements CourseRepository {}

void main() {
  final now = DateTime(2026, 10, 5, 10);
  final date = LocalDate(2026, 10, 5);
  late _Gateway gateway;
  late _Settings settings;
  late _Courses courses;
  late AttendanceNotifier notifier;
  late List<PlannedNotification> shown;

  AttendanceRecord record(
    AttendanceStatus status, {
    String slotId = 'slot',
    AttendanceSource source = AttendanceSource.automatic,
    DateTime? checkInAt,
  }) => AttendanceRecord(
    id: '$slotId-${status.name}',
    slotId: slotId,
    courseId: 'course',
    occurrenceDate: date,
    status: status,
    source: source,
    evaluatedAt: now,
    checkInAt: checkInAt,
  );

  setUpAll(() {
    registerFallbackValue(
      PlannedNotification(
        id: 0,
        kind: NotificationKind.attendanceResult,
        at: now,
      ),
    );
  });

  setUp(() {
    gateway = _Gateway();
    settings = _Settings();
    courses = _Courses();
    shown = [];
    when(() => settings.load()).thenAnswer((_) async => UserSettings());
    when(() => courses.getAll()).thenAnswer(
      (_) async => [Course(id: 'course', name: 'Mathematics')],
    );
    when(
      () => gateway.ensurePermission(),
    ).thenAnswer((_) async => NotificationPermission.granted);
    when(() => gateway.show(any())).thenAnswer((invocation) async {
      shown.add(invocation.positionalArguments.single as PlannedNotification);
    });
    notifier = AttendanceNotifier(
      gateway: gateway,
      settingsRepository: settings,
      courseRepository: courses,
    );
  });

  for (final status in AttendanceStatus.values) {
    test(
      'automatic ${status.name} is notified only for present/late/absent',
      () async {
        final ids = await notifier.notify([record(status)]);
        final notifiable = {
          AttendanceStatus.present,
          AttendanceStatus.late,
          AttendanceStatus.absent,
        }.contains(status);
        expect(ids.length, notifiable ? 1 : 0);
        expect(shown.length, notifiable ? 1 : 0);
        if (notifiable) {
          expect(shown.single.payload['status'], status.name);
          expect(shown.single.payload['courseName'], 'Mathematics');
          expect(shown.single.at, now.toUtc());
        }
      },
    );
  }

  test('all manual statuses are skipped', () async {
    expect(
      await notifier.notify([
        for (final status in AttendanceStatus.values)
          record(status, source: AttendanceSource.manual),
      ]),
      isEmpty,
    );
    verifyNever(() => gateway.ensurePermission());
    expect(shown, isEmpty);
  });

  test('disabled notifications do not query courses or permissions', () async {
    when(
      () => settings.load(),
    ).thenAnswer((_) async => UserSettings(notificationsEnabled: false));
    expect(await notifier.notify([record(AttendanceStatus.present)]), isEmpty);
    verifyNever(() => courses.getAll());
    verifyNever(() => gateway.ensurePermission());
  });

  test('denied permission does not prompt or show', () async {
    when(
      () => gateway.ensurePermission(),
    ).thenAnswer((_) async => NotificationPermission.denied);
    expect(await notifier.notify([record(AttendanceStatus.absent)]), isEmpty);
    verifyNever(() => gateway.requestPermission());
    expect(shown, isEmpty);
  });

  test(
    'multiple records have stable IDs and retain UTC check-in times',
    () async {
      final checkIn = DateTime(2026, 10, 5, 9, 12);
      final records = [
        record(AttendanceStatus.present, slotId: 'a', checkInAt: checkIn),
        record(AttendanceStatus.late, slotId: 'b', checkInAt: checkIn),
        record(AttendanceStatus.absent, slotId: 'c'),
      ];
      final ids = await notifier.notify(records);
      expect(ids, [
        for (final value in records)
          notificationId(
            kind: NotificationKind.attendanceResult,
            slotId: value.slotId,
            occurrenceDate: date,
          ),
      ]);
      expect(
        shown.first.payload['checkInAt'],
        checkIn.toUtc().toIso8601String(),
      );
      expect(shown.last.payload.containsKey('checkInAt'), isFalse);
      verify(() => courses.getAll()).called(1);
    },
  );

  test(
    'duplicates in one batch produce only one immediate notification',
    () async {
      final value = record(AttendanceStatus.present);
      expect(await notifier.notify([value, value]), hasLength(1));
      expect(shown, hasLength(1));
    },
  );

  test(
    'deleted course still produces a notification with localized fallback',
    () async {
      when(() => courses.getAll()).thenAnswer((_) async => []);
      await notifier.notify([record(AttendanceStatus.absent)]);
      expect(shown.single.payload.containsKey('courseName'), isFalse);
    },
  );

  test('empty written-record batch is a no-op', () async {
    expect(await notifier.notify([]), isEmpty);
    expect(shown, isEmpty);
    verifyNever(() => gateway.ensurePermission());
  });
}
