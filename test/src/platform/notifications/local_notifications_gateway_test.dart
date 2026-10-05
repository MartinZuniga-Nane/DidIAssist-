import 'package:clock/clock.dart';
import 'package:did_i_assist/src/domain/models/planned_notification.dart';
import 'package:did_i_assist/src/domain/repositories/notification_gateway.dart';
import 'package:did_i_assist/src/platform/notifications/local_notifications_gateway.dart';
import 'package:did_i_assist/src/platform/notifications/notification_message_builder.dart';
import 'package:did_i_assist/src/platform/notifications/notification_payload_codec.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final originalPlatform = AndroidFlutterLocalNotificationsPlugin();
  final now = DateTime.utc(2030, 3, 10, 6);
  late LocalNotificationsGateway gateway;
  late List<MethodCall> calls;
  late bool? permission;
  late bool? exactAllowed;
  late List<Map<String, Object?>> pending;
  const codec = NotificationPayloadCodec();

  PlannedNotification departure({DateTime? at}) => PlannedNotification(
    id: 1,
    kind: NotificationKind.departureReminder,
    at: at ?? DateTime.utc(2030, 3, 10, 7, 30),
    payload: const {
      'courseName': 'Mathematics',
      'placeName': 'Campus',
      'etaMinutes': '20',
    },
  );
  Map<Object?, Object?> arguments(MethodCall call) =>
      call.arguments as Map<Object?, Object?>;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
    calls = [];
    permission = true;
    exactAllowed = false;
    pending = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'initialize' => true,
        'areNotificationsEnabled' ||
        'requestNotificationsPermission' => permission,
        'canScheduleExactNotifications' => exactAllowed,
        'checkPermissions' => {'isEnabled': permission ?? false},
        'requestPermissions' => permission,
        'pendingNotificationRequests' => pending,
        _ => null,
      };
    });
    gateway = LocalNotificationsGateway(
      messageBuilder: await NotificationMessageBuilder.create(
        const Locale('es'),
      ),
      timezoneName: () async => 'America/New_York',
      timeSource: Clock.fixed(now),
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    FlutterLocalNotificationsPlatform.instance = originalPlatform;
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'initializes once and creates both localized Android channels',
    () async {
      await gateway.initialize();
      await gateway.initialize();
      expect(calls.where((call) => call.method == 'initialize'), hasLength(1));
      final channels = calls
          .where((call) => call.method == 'createNotificationChannel')
          .toList();
      expect(channels, hasLength(2));
      final first = arguments(channels.first);
      final second = arguments(channels.last);
      expect(first['id'], LocalNotificationsGateway.departureChannelId);
      expect(first['name'], 'Recordatorios de salida');
      expect(second['id'], LocalNotificationsGateway.attendanceChannelId);
      expect(second['name'], 'Resultados de asistencia');
    },
  );

  test('failed native initialization can be retried', () async {
    var attempts = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'initialize') {
        if (attempts++ == 0) {
          throw PlatformException(code: 'temporarily_unavailable');
        }
        return true;
      }
      return null;
    });
    await expectLater(gateway.initialize(), throwsA(isA<PlatformException>()));
    await gateway.initialize();
    expect(attempts, 2);
  });

  for (final enabled in [true, false, null]) {
    test('maps Android permission $enabled without prompting', () async {
      permission = enabled;
      expect(
        await gateway.ensurePermission(),
        enabled == null
            ? NotificationPermission.unavailable
            : enabled
            ? NotificationPermission.granted
            : NotificationPermission.denied,
      );
      expect(
        calls.where((call) => call.method == 'requestNotificationsPermission'),
        isEmpty,
      );
    });
  }

  test(
    'explicit permission request uses Android notification permission only',
    () async {
      expect(await gateway.requestPermission(), NotificationPermission.granted);
      expect(
        calls.where((call) => call.method == 'requestNotificationsPermission'),
        hasLength(1),
      );
      expect(
        calls.where((call) => call.method == 'requestExactAlarmsPermission'),
        isEmpty,
      );
    },
  );

  for (final allowed in [true, false, null]) {
    test(
      'exact alarm capability $allowed chooses the appropriate scheduling mode',
      () async {
        exactAllowed = allowed;
        await gateway.schedule(departure());
        final args = arguments(
          calls.singleWhere((call) => call.method == 'zonedSchedule'),
        );
        final specifics = args['platformSpecifics']! as Map<Object?, Object?>;
        expect(
          specifics['scheduleMode'],
          (allowed ?? false) ? 'exactAllowWhileIdle' : 'inexactAllowWhileIdle',
        );
        expect(
          specifics['channelId'],
          LocalNotificationsGateway.departureChannelId,
        );
        expect(args['timeZoneName'], 'America/New_York');
        expect(args['scheduledDateTime'], startsWith('2030-03-10T03:30'));
        expect(codec.decode(1, args['payload']! as String), departure());
      },
    );
  }

  test(
    'zoned scheduling preserves the instant on both sides of a DST jump',
    () async {
      await gateway.schedule(departure(at: DateTime.utc(2030, 3, 10, 6, 30)));
      await gateway.schedule(departure());
      final schedules = calls
          .where((call) => call.method == 'zonedSchedule')
          .toList();
      expect(
        arguments(schedules.first)['scheduledDateTime'],
        startsWith('2030-03-10T01:30'),
      );
      expect(
        arguments(schedules.last)['scheduledDateTime'],
        startsWith('2030-03-10T03:30'),
      );
    },
  );

  test(
    'past or exactly-now schedule is rejected before the native call',
    () async {
      for (final at in [now, now.subtract(const Duration(microseconds: 1))]) {
        await expectLater(
          gateway.schedule(departure(at: at)),
          throwsArgumentError,
        );
      }
      expect(calls.where((call) => call.method == 'zonedSchedule'), isEmpty);
    },
  );

  test(
    'immediate attendance uses the attendance channel and localized text',
    () async {
      final notification = PlannedNotification(
        id: 2,
        kind: NotificationKind.attendanceResult,
        at: now,
        payload: const {'status': 'absent', 'courseName': 'Mathematics'},
      );
      await gateway.show(notification);
      final args = arguments(
        calls.singleWhere((call) => call.method == 'show'),
      );
      expect(args['title'], 'Inasistencia registrada');
      expect(args['body'], 'Se registró tu inasistencia a Mathematics.');
      final specifics = args['platformSpecifics']! as Map<Object?, Object?>;
      expect(
        specifics['channelId'],
        LocalNotificationsGateway.attendanceChannelId,
      );
      expect(codec.decode(2, args['payload']! as String), notification);
    },
  );

  test(
    'pending IDs include all requests; plans only include owned payloads',
    () async {
      pending = [
        {
          'id': 1,
          'title': 'Reminder',
          'body': 'Body',
          'payload': codec.encode(departure()),
        },
        {'id': 99, 'title': 'Other', 'body': 'Body', 'payload': 'other'},
      ];
      expect(await gateway.pendingIds(), {1, 99});
      expect(await gateway.pendingNotifications(), [departure()]);
    },
  );

  test('cancelWhere cancels only matching owned notifications', () async {
    final attendance = PlannedNotification(
      id: 2,
      kind: NotificationKind.attendanceResult,
      at: now,
      payload: const {'status': 'absent'},
    );
    pending = [
      {'id': 1, 'payload': codec.encode(departure())},
      {'id': 2, 'payload': codec.encode(attendance)},
      {'id': 99, 'payload': 'other'},
    ];
    expect(
      await gateway.cancelWhere(
        (notification) =>
            notification.kind == NotificationKind.departureReminder,
      ),
      1,
    );
    final canceled = calls.where((call) => call.method == 'cancel').toList();
    expect(canceled, hasLength(1));
    expect(arguments(canceled.single)['id'], 1);
  });

  test(
    'iOS initializes silently and exposes explicit permission requests',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      FlutterLocalNotificationsPlatform.instance =
          IOSFlutterLocalNotificationsPlugin();
      await gateway.initialize();
      final initialization = arguments(
        calls.singleWhere((call) => call.method == 'initialize'),
      );
      expect(initialization['requestAlertPermission'], isFalse);
      expect(initialization['requestBadgePermission'], isFalse);
      expect(initialization['requestSoundPermission'], isFalse);
      expect(await gateway.ensurePermission(), NotificationPermission.granted);
      expect(
        calls.where((call) => call.method == 'requestPermissions'),
        isEmpty,
      );
      expect(await gateway.requestPermission(), NotificationPermission.granted);
      final request = arguments(
        calls.singleWhere((call) => call.method == 'requestPermissions'),
      );
      expect(request['alert'], isTrue);
      expect(request['sound'], isTrue);
      expect(request['badge'], isTrue);
    },
  );

  test(
    'iOS zoned scheduling carries the local timezone and owned payload',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      FlutterLocalNotificationsPlatform.instance =
          IOSFlutterLocalNotificationsPlugin();
      await gateway.schedule(departure());
      final args = arguments(
        calls.singleWhere((call) => call.method == 'zonedSchedule'),
      );
      expect(args['timeZoneName'], 'America/New_York');
      expect(codec.decode(1, args['payload']! as String), departure());
      expect(
        calls.where((call) => call.method == 'canScheduleExactNotifications'),
        isEmpty,
      );
    },
  );
}
