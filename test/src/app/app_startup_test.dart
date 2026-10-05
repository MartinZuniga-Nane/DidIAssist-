import 'dart:async';

import 'package:clock/clock.dart';
import 'package:did_i_assist/src/app/app_services.dart';
import 'package:did_i_assist/src/app/app_startup.dart';
import 'package:did_i_assist/src/app/didi_assist_app.dart';
import 'package:did_i_assist/src/app/open_app_services.dart';
import 'package:did_i_assist/src/domain/location/position_fix.dart';
import 'package:did_i_assist/src/domain/repositories/notification_gateway.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../data/database/test_database.dart';
import '../domain/services/fixtures.dart';
import 'fakes.dart';

final class _Notifications extends Mock implements NotificationGateway {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppStartup startup;
  late _Notifications notifications;
  late FakeGeofenceRegistrar geofences;
  late List<String> calls;
  late List<Object> errors;
  final source = occurrence();
  final now = DateTime(2026, 10, 5, 8);

  Future<AppServices> open(NotificationGateway gateway) async {
    calls.add('services.open');
    return openAppServices(
      database: createTestDatabase(),
      geofenceRegistrar: geofences,
      positionProvider: FakePositionProvider(
        PositionFix(
          position: source.place.center,
          timestamp: now,
        ),
      ),
      permissions: FakePermissions(),
      sampleTasks: FakeClassSampleGateway(),
      notifications: gateway,
      timeSource: Clock.fixed(now),
    );
  }

  setUp(() {
    calls = [];
    errors = [];
    geofences = FakeGeofenceRegistrar();
    notifications = _Notifications();
    when(notifications.ensurePermission).thenAnswer((_) async {
      calls.add('notifications.initialize');
      return NotificationPermission.granted;
    });
    when(notifications.pendingNotifications).thenAnswer((_) async {
      calls.add('reminders');
      return [];
    });
    when(notifications.pendingIds).thenAnswer((_) async => {});
    startup = AppStartup(
      createNotifications: () async {
        calls.add('notifications.create');
        return notifications;
      },
      openServices: open,
      startWork: (_) async => calls.add('background.start'),
      onError: (error, _) => errors.add(error),
    );
  });
  tearDown(() => startup.dispose());

  test(
    'initializes notifications before opening services and starting work',
    () async {
      await startup.initialize();
      expect(calls, [
        'notifications.create',
        'notifications.initialize',
        'services.open',
        'background.start',
        'reminders',
      ]);
      expect(startup.services, isNotNull);
      expect(errors, isEmpty);
      await startup.initialize();
      expect(calls.where((call) => call == 'services.open'), hasLength(1));
    },
  );

  for (final permission in [
    NotificationPermission.denied,
    NotificationPermission.unavailable,
  ]) {
    test('$permission still opens services without prompting', () async {
      when(notifications.ensurePermission).thenAnswer((_) async => permission);
      await startup.initialize();
      expect(startup.services, isNotNull);
      expect(
        calls,
        containsAll(['services.open', 'background.start', 'reminders']),
      );
      expect(errors, isEmpty);
      verifyNever(notifications.requestPermission);
    });
  }

  test(
    'notification initialization failure is captured and services still open',
    () async {
      final error = StateError('notifications unavailable');
      when(notifications.ensurePermission).thenThrow(error);
      await startup.initialize();
      expect(startup.services, isNotNull);
      expect(errors, [error]);
      expect(calls, containsAll(['background.start', 'reminders']));
    },
  );

  test(
    'notification factory failure does not prevent database composition',
    () async {
      await startup.dispose();
      final error = StateError('notification setup failed');
      startup = AppStartup(
        createNotifications: () async => throw error,
        openServices: open,
        startWork: (_) async => calls.add('background.start'),
        onError: (error, _) => errors.add(error),
      );
      await startup.initialize();
      expect(startup.services, isNotNull);
      expect(calls, contains('background.start'));
      expect(errors, everyElement(same(error)));
      expect(errors, hasLength(2));
    },
  );

  test(
    'registrar failure does not suppress departure reconciliation',
    () async {
      await startup.dispose();
      geofences.failSync = true;
      startup = AppStartup(
        createNotifications: () async => notifications,
        openServices: open,
        startWork: (services) => services.syncGeofencesWhenPermitted(),
        onError: (error, _) => errors.add(error),
      );
      await startup.initialize();
      expect(errors, hasLength(1));
      expect(calls, contains('reminders'));
      expect(startup.services, isNotNull);
    },
  );

  test('reminder failure is captured and the backend remains usable', () async {
    final error = StateError('reminder scheduling failed');
    when(notifications.pendingNotifications).thenThrow(error);
    await startup.initialize();
    expect(errors, [error]);
    expect(await startup.services!.settings.load(), isNotNull);
  });

  test(
    'opening failure is captured and background work is not started',
    () async {
      await startup.dispose();
      final error = StateError('database unavailable');
      startup = AppStartup(
        createNotifications: () async => notifications,
        openServices: (_) async => throw error,
        startWork: (_) async => calls.add('background.start'),
        onError: (error, _) => errors.add(error),
      );
      await startup.initialize();
      expect(startup.services, isNull);
      expect(errors, [error]);
      expect(calls, isNot(contains('background.start')));
    },
  );

  test('detach closes services and subscriptions exactly once', () async {
    await startup.initialize();
    final services = startup.services!;
    startup.didChangeAppLifecycleState(AppLifecycleState.detached);
    final closed = startup.dispose();
    expect(startup.dispose(), same(closed));
    await closed;
    await expectLater(services.settings.load(), throwsStateError);
    await startup.initialize();
    expect(calls.where((call) => call == 'services.open'), hasLength(1));
  });

  test(
    'dispose during opening waits and closes the late-created services',
    () async {
      await startup.dispose();
      final pending = Completer<AppServices>();
      final entered = Completer<void>();
      startup = AppStartup(
        createNotifications: () async => notifications,
        openServices: (_) {
          entered.complete();
          return pending.future;
        },
        startWork: (_) async => calls.add('background.start'),
        onError: (error, _) => errors.add(error),
      );
      final initializing = startup.initialize();
      await entered.future;
      final closing = startup.dispose();
      final services = await open(FakeNotifications());
      await services.settings.load();
      pending.complete(services);
      await initializing;
      await closing;
      expect(calls, isNot(contains('background.start')));
      await expectLater(services.settings.load(), throwsStateError);
    },
  );

  testWidgets('first frame is visible while notification setup is pending', (
    tester,
  ) async {
    await tester.runAsync(startup.dispose);
    final pending = Completer<NotificationGateway>();
    startup = AppStartup(
      createNotifications: () => pending.future,
      openServices: open,
      onError: (error, _) => errors.add(error),
    )..launch(const DidIAssistApp());
    await tester.pump();
    expect(find.text('DidIAssist'), findsOneWidget);
    expect(startup.services, isNull);
    expect(calls, isEmpty);
    late Future<void> closing;
    await tester.runAsync(() async {
      closing = startup.dispose();
    });
    pending.complete(FakeNotifications());
    await tester.pump();
    await tester.runAsync(() => closing);
    expect(calls, isEmpty);
    expect(errors, isEmpty);
    expect(() => startup.launch(const DidIAssistApp()), throwsStateError);
  });
}
