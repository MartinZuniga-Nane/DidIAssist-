import 'package:clock/clock.dart';
import 'package:did_i_assist/src/core/local_date.dart';
import 'package:did_i_assist/src/domain/models/models.dart';
import 'package:did_i_assist/src/domain/models/planned_notification.dart';
import 'package:did_i_assist/src/domain/repositories/course_repository.dart';
import 'package:did_i_assist/src/domain/repositories/notification_gateway.dart';
import 'package:did_i_assist/src/domain/repositories/place_repository.dart';
import 'package:did_i_assist/src/domain/repositories/settings_repository.dart';
import 'package:did_i_assist/src/domain/repositories/trip_repository.dart';
import 'package:did_i_assist/src/domain/services/departure_service.dart';
import 'package:did_i_assist/src/domain/services/reminder_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';

class _Courses extends Mock implements CourseRepository {}

class _Places extends Mock implements PlaceRepository {}

class _Settings extends Mock implements SettingsRepository {}

class _Trips extends Mock implements TripRepository {}

class _Gateway extends Mock implements NotificationGateway {}

void main() {
  final now = DateTime(2026, 10, 5, 8);
  final classOccurrence = occurrence();
  late _Courses courses;
  late _Places places;
  late _Settings settings;
  late _Trips trips;
  late _Gateway gateway;
  late ReminderService service;
  late Map<int, PlannedNotification> pending;
  late Set<int> unrelated;
  late List<PlannedNotification> scheduled;
  late List<int> canceled;
  late UserSettings savedSettings;

  setUpAll(() {
    registerFallbackValue(
      PlannedNotification(
        id: 0,
        kind: NotificationKind.departureReminder,
        at: now,
      ),
    );
  });

  setUp(() {
    courses = _Courses();
    places = _Places();
    settings = _Settings();
    trips = _Trips();
    gateway = _Gateway();
    pending = {};
    unrelated = {};
    scheduled = [];
    canceled = [];
    savedSettings = UserSettings();
    when(
      () => courses.getAll(),
    ).thenAnswer((_) async => [classOccurrence.course]);
    when(
      () => courses.getSlots(),
    ).thenAnswer((_) async => [classOccurrence.slot]);
    when(
      () => places.getAll(),
    ).thenAnswer((_) async => [homePlace(), campusPlace()]);
    when(() => settings.load()).thenAnswer((_) async => savedSettings);
    when(
      () => trips.getRecent(
        fromPlaceId: 'home',
        toPlaceId: 'campus',
      ),
    ).thenAnswer((_) async => []);
    when(
      () => gateway.pendingNotifications(),
    ).thenAnswer(
      (_) async => pending.values.map((item) => item.copyWith()).toList(),
    );
    when(
      () => gateway.pendingIds(),
    ).thenAnswer((_) async => {...pending.keys, ...unrelated});
    when(
      () => gateway.ensurePermission(),
    ).thenAnswer((_) async => NotificationPermission.granted);
    when(() => gateway.schedule(any())).thenAnswer((invocation) async {
      final item = invocation.positionalArguments.single as PlannedNotification;
      scheduled.add(item);
      pending[item.id] = item;
    });
    when(() => gateway.cancel(any())).thenAnswer((invocation) async {
      final id = invocation.positionalArguments.single as int;
      canceled.add(id);
      pending.remove(id);
    });
    service = ReminderService(
      courseRepository: courses,
      placeRepository: places,
      settingsRepository: settings,
      departureService: DepartureService(
        placeRepository: places,
        settingsRepository: settings,
        tripRepository: trips,
        timeSource: Clock.fixed(now),
      ),
      gateway: gateway,
      timeSource: Clock.fixed(now),
    );
  });

  PlannedNotification stale(int id, NotificationKind kind) =>
      PlannedNotification(id: id, kind: kind, at: now);

  test('plans from Home, schedules once, and remains idempotent', () async {
    final first = await service.reconcile();
    expect(first.plannedCount, 1);
    expect(first.scheduledIds, [scheduled.single.id]);
    expect(scheduled.single.at, DateTime(2026, 10, 5, 8, 3).toUtc());
    expect(scheduled.single.payload['etaMinutes'], '52');
    final second = await service.reconcile();
    expect(second.scheduledIds, isEmpty);
    expect(second.canceledIds, isEmpty);
    expect(second.skippedIds, isEmpty);
    expect(scheduled, hasLength(1));
    verifyNever(() => gateway.requestPermission());
  });

  test(
    'cancels stale departure reminders and leaves unrelated IDs alone',
    () async {
      pending[1] = stale(1, NotificationKind.departureReminder);
      pending[2] = stale(2, NotificationKind.attendanceResult);
      unrelated.add(3);
      final summary = await service.reconcile();
      expect(summary.canceledIds, [1]);
      expect(canceled, [1]);
      expect(pending.containsKey(2), isTrue);
      expect(unrelated, {3});
    },
  );

  test(
    'a changed leaveBy or payload replaces the same deterministic ID',
    () async {
      await service.reconcile();
      final original = scheduled.single;
      savedSettings = savedSettings.copyWith(departureBufferMinutes: 6);
      final changed = await service.reconcile();
      expect(changed.scheduledIds, [original.id]);
      expect(scheduled.last.at, DateTime(2026, 10, 5, 8, 2).toUtc());
      when(() => courses.getAll()).thenAnswer(
        (_) async => [classOccurrence.course.copyWith(name: 'Physics')],
      );
      await service.reconcile();
      expect(scheduled.last.payload['courseName'], 'Physics');
      expect(scheduled, hasLength(3));
    },
  );

  test(
    'disabled notifications cancel reminders without loading schedules',
    () async {
      savedSettings = UserSettings(notificationsEnabled: false);
      pending[1] = stale(1, NotificationKind.departureReminder);
      pending[2] = stale(2, NotificationKind.attendanceResult);
      final result = await service.reconcile();
      expect(result.plannedCount, 0);
      expect(result.canceledIds, [1]);
      expect(scheduled, isEmpty);
      verifyNever(() => courses.getAll());
      verifyNever(() => gateway.ensurePermission());
    },
  );

  test(
    'missing Home cancels stale reminders instead of inventing an origin',
    () async {
      when(() => places.getAll()).thenAnswer((_) async => [campusPlace()]);
      pending[1] = stale(1, NotificationKind.departureReminder);
      final result = await service.reconcile();
      expect(result.plannedCount, 0);
      expect(result.canceledIds, [1]);
      expect(scheduled, isEmpty);
    },
  );

  test(
    'permission denied skips scheduling but still cancels stale reminders',
    () async {
      when(
        () => gateway.ensurePermission(),
      ).thenAnswer((_) async => NotificationPermission.denied);
      pending[1] = stale(1, NotificationKind.departureReminder);
      final result = await service.reconcile();
      expect(result.skippedIds, hasLength(1));
      expect(result.canceledIds, [1]);
      expect(scheduled, isEmpty);
      verifyNever(() => gateway.requestPermission());
    },
  );

  test('an unrelated pending ID collision is preserved and reported', () async {
    await service.reconcile();
    final id = scheduled.single.id;
    pending.clear();
    scheduled.clear();
    unrelated.add(id);
    final result = await service.reconcile();
    expect(result.skippedIds, [id]);
    expect(scheduled, isEmpty);
    expect(canceled, isEmpty);
  });

  test(
    'next 24h include next-day classes and exclude the upper bound',
    () async {
      final starts = [
        now.subtract(const Duration(minutes: 1)),
        now,
        now.add(const Duration(hours: 23)),
        now.add(const Duration(hours: 24)),
      ];
      final slots = [
        for (var i = 0; i < starts.length; i++)
          classOccurrence.slot.copyWith(
            id: 'slot-$i',
            weekday: starts[i].weekday,
            startMinute: starts[i].hour * 60 + starts[i].minute,
          ),
      ];
      when(() => courses.getSlots()).thenAnswer((_) async => slots);
      final result = await service.reconcile();
      expect(result.plannedCount, 1);
      expect(scheduled.single.payload['slotId'], 'slot-2');
      verify(() => courses.getAll()).called(1);
      verify(() => courses.getSlots()).called(1);
    },
  );

  test('inactive semester bounds prevent reminders', () async {
    when(() => courses.getAll()).thenAnswer(
      (_) async => [
        classOccurrence.course.copyWith(
          activeFrom: () => LocalDate(2026, 10, 6),
        ),
      ],
    );
    expect((await service.reconcile()).plannedCount, 0);
    expect(scheduled, isEmpty);
  });

  test('summary uses immutable value equality', () {
    final first = ReminderSummary(
      plannedCount: 2,
      scheduledIds: const [1],
      canceledIds: const [2],
      skippedIds: const [3],
    );
    expect(
      first,
      ReminderSummary(
        plannedCount: 2,
        scheduledIds: const [1],
        canceledIds: const [2],
        skippedIds: const [3],
      ),
    );
    expect(first.scheduledIds.clear, throwsUnsupportedError);
  });
}
