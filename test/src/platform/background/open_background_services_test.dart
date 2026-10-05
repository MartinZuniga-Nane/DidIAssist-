import 'package:clock/clock.dart';
import 'package:did_i_assist/src/app/app_services.dart';
import 'package:did_i_assist/src/app/background_operations.dart';
import 'package:did_i_assist/src/app/open_app_services.dart';
import 'package:did_i_assist/src/domain/location/geofence_transition.dart';
import 'package:did_i_assist/src/domain/location/position_fix.dart';
import 'package:did_i_assist/src/domain/models/models.dart';
import 'package:did_i_assist/src/domain/repositories/notification_gateway.dart';
import 'package:did_i_assist/src/platform/background/open_background_services.dart';
import 'package:did_i_assist/src/platform/notifications/lazy_notification_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../app/fakes.dart';
import '../../data/database/test_database.dart';
import '../../domain/services/fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final source = occurrence();
  late AppServices services;
  late FakeNotifications notifications;
  late DateTime now;

  Future<void> open({NotificationGateway? gateway}) async {
    services = await openBackgroundServices(
      openServices: ({required attendanceListeners}) => openAppServices(
        database: createTestDatabase(),
        geofenceRegistrar: FakeGeofenceRegistrar(),
        positionProvider: FakePositionProvider(
          PositionFix(
            position: source.place.center,
            timestamp: now,
          ),
        ),
        permissions: FakePermissions(),
        sampleTasks: FakeClassSampleGateway(),
        notifications: gateway ?? notifications,
        timeSource: Clock.fixed(now),
        attendanceListeners: attendanceListeners,
      ),
    );
    await services.places.save(source.place);
    await services.courses.saveCourse(source.course);
    await services.courses.saveSlot(source.slot);
  }

  setUp(() {
    notifications = FakeNotifications();
    now = DateTime(2026, 10, 5, 9, 1);
  });

  for (final status in [
    AttendanceStatus.present,
    AttendanceStatus.late,
    AttendanceStatus.absent,
  ]) {
    test('background composition notifies automatic ${status.name}', () async {
      now = switch (status) {
        AttendanceStatus.late => DateTime(2026, 10, 5, 9, 12),
        AttendanceStatus.absent => DateTime(2026, 10, 5, 10, 31),
        _ => now,
      };
      await open();
      addTearDown(services.dispose);
      if (status != AttendanceStatus.absent) {
        await services.events.append(
          transition(
            LocationEventType.geofenceEnter,
            status == AttendanceStatus.late
                ? DateTime(2026, 10, 5, 9, 11)
                : source.start,
            placeId: source.place.id,
          ),
        );
      }
      final result = await services.pipeline.onPeriodicTick();
      expect(result.succeeded, isTrue);
      expect(result.attendance.single.status, status);
      expect(notifications.shown.single.payload['status'], status.name);
      await services.pipeline.onPeriodicTick();
      expect(notifications.shown, hasLength(1));
    });
  }

  test('manual attendance remains untouched and is not notified', () async {
    await open();
    addTearDown(services.dispose);
    final manual = await services.attendanceService.markManually(
      source.slot.id,
      source.occurrenceDate,
      AttendanceStatus.excused,
    );
    final result = await services.pipeline.onGeofenceTransition(
      GeofenceTransition(
        placeIds: [source.place.id],
        type: LocationEventType.geofenceEnter,
        receivedAt: source.start,
      ),
    );
    expect(result.attendance, isEmpty);
    expect(notifications.shown, isEmpty);
    expect(
      await services.attendance.findBySlotAndDate(
        source.slot.id,
        source.occurrenceDate,
      ),
      manual,
    );
  });

  test(
    'notification failure cannot roll back recorded evidence or attendance',
    () async {
      notifications.showError = StateError('notification failed');
      await open();
      addTearDown(services.dispose);
      final result = await services.pipeline.onGeofenceTransition(
        GeofenceTransition(
          placeIds: [source.place.id],
          type: LocationEventType.geofenceEnter,
          receivedAt: source.start,
        ),
      );
      expect(result.failures.single.stage, BackgroundStage.notifyListener);
      expect(await services.events.query(until: now), hasLength(1));
      expect(
        await services.attendance.findBySlotAndDate(
          source.slot.id,
          source.occurrenceDate,
        ),
        result.attendance.single,
      );
    },
  );

  test(
    'notification setup is deferred until evidence and attendance are durable',
    () async {
      var attempted = false;
      final gateway = LazyNotificationGateway(() async {
        attempted = true;
        expect(await services.events.query(until: now), hasLength(1));
        expect(
          await services.attendance.findBySlotAndDate(
            source.slot.id,
            source.occurrenceDate,
          ),
          isNotNull,
        );
        throw StateError('headless notification setup failed');
      });
      await open(gateway: gateway);
      addTearDown(services.dispose);
      expect(attempted, isFalse);
      await services.pipeline.handle(
        GeofenceTransition(
          placeIds: [source.place.id],
          type: LocationEventType.geofenceEnter,
          receivedAt: source.start,
        ),
      );
      expect(attempted, isTrue);
      expect(await services.events.query(until: now), hasLength(1));
    },
  );

  test(
    'disabled notifications never initialize their headless platform port',
    () async {
      var attempted = false;
      final gateway = LazyNotificationGateway(() async {
        attempted = true;
        throw StateError('should not be called');
      });
      await open(gateway: gateway);
      addTearDown(services.dispose);
      await services.settings.save(UserSettings(notificationsEnabled: false));
      await services.pipeline.handle(
        GeofenceTransition(
          placeIds: [source.place.id],
          type: LocationEventType.geofenceEnter,
          receivedAt: source.start,
        ),
      );
      expect(attempted, isFalse);
    },
  );
}
