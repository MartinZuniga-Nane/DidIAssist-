import 'package:clock/clock.dart';
import 'package:did_i_assist/src/app/app_services.dart';
import 'package:did_i_assist/src/app/start_background_work.dart';
import 'package:did_i_assist/src/core/local_date.dart';
import 'package:did_i_assist/src/domain/location/location_permission_gateway.dart';
import 'package:did_i_assist/src/domain/location/position_fix.dart';
import 'package:did_i_assist/src/domain/services/class_sample_planner.dart';
import 'package:did_i_assist/src/platform/background/background_scheduler.dart';
import 'package:did_i_assist/src/platform/background/background_task_names.dart';
import 'package:did_i_assist/src/platform/background/callback_dispatcher.dart';
import 'package:did_i_assist/src/platform/background/workmanager_class_sample_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:workmanager/workmanager.dart';

import '../../app/fakes.dart';
import '../../data/database/test_database.dart';
import '../../domain/services/fixtures.dart';

final class _Workmanager extends Mock implements Workmanager {}

void main() {
  late _Workmanager manager;
  final now = DateTime(2026, 10, 5, 8);

  setUpAll(() {
    registerFallbackValue(() {});
    registerFallbackValue(Constraints());
  });
  setUp(() {
    manager = _Workmanager();
    when(() => manager.initialize(any())).thenAnswer((_) async {});
    when(
      () => manager.registerPeriodicTask(
        any(),
        any(),
        frequency: any(named: 'frequency'),
        flexInterval: any(named: 'flexInterval'),
        initialDelay: any(named: 'initialDelay'),
        existingWorkPolicy: any(named: 'existingWorkPolicy'),
        constraints: any(named: 'constraints'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => manager.registerOneOffTask(
        any(),
        any(),
        inputData: any(named: 'inputData'),
        initialDelay: any(named: 'initialDelay'),
        existingWorkPolicy: any(named: 'existingWorkPolicy'),
        constraints: any(named: 'constraints'),
      ),
    ).thenAnswer((_) async {});
    when(() => manager.cancelByUniqueName(any())).thenAnswer((_) async {});
  });

  test(
    'initialization uses the top-level dispatcher and 30-minute offline work',
    () async {
      final scheduler = BackgroundScheduler(manager: manager);
      await Future.wait([scheduler.initialize(), scheduler.initialize()]);
      verify(() => manager.initialize(callbackDispatcher)).called(1);
      final constraints =
          verify(
                () => manager.registerPeriodicTask(
                  BackgroundTaskNames.periodic,
                  BackgroundTaskNames.periodic,
                  frequency: const Duration(minutes: 30),
                  flexInterval: const Duration(minutes: 5),
                  initialDelay: const Duration(minutes: 30),
                  existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
                  constraints: captureAny(named: 'constraints'),
                ),
              ).captured.single
              as Constraints;
      expect(constraints.networkType, NetworkType.notRequired);
      expect(constraints.requiresBatteryNotLow, isTrue);
      expect(constraints.requiresStorageNotLow, isTrue);
    },
  );

  test('initialization failures can retry', () async {
    final scheduler = BackgroundScheduler(manager: manager);
    when(
      () => manager.initialize(any()),
    ).thenThrow(StateError('initialization failed'));
    await expectLater(scheduler.initialize(), throwsStateError);
    when(() => manager.initialize(any())).thenAnswer((_) async {});
    await scheduler.initialize();
    verify(() => manager.initialize(callbackDispatcher)).called(2);
  });

  for (final policy in ClassSampleSchedulePolicy.values) {
    test(
      'sample adapter forwards ${policy.name}, delay and canonical payload',
      () async {
        final task = ClassSampleTask(
          slotId: 'slot',
          date: LocalDate(2026, 10, 5),
          offsetMinutes: 1,
          classStart: DateTime(2026, 10, 5, 9),
          runAt: DateTime(2026, 10, 5, 9, 1),
        );
        final gateway = WorkmanagerClassSampleGateway(
          manager: manager,
          timeSource: Clock.fixed(now),
        );
        await gateway.schedule(task, policy);
        final captured = verify(
          () => manager.registerOneOffTask(
            task.uniqueName,
            BackgroundTaskNames.classSample,
            inputData: captureAny(named: 'inputData'),
            initialDelay: const Duration(minutes: 61),
            existingWorkPolicy: policy == ClassSampleSchedulePolicy.keep
                ? ExistingWorkPolicy.keep
                : ExistingWorkPolicy.replace,
            constraints: captureAny(named: 'constraints'),
          ),
        ).captured;
        expect(captured.first, {
          'slotId': 'slot',
          'date': '2026-10-05',
          'offsetMinutes': 1,
        });
        expect(
          (captured.last as Constraints).networkType,
          NetworkType.notRequired,
        );
        await gateway.cancel(task.uniqueName);
        verify(() => manager.cancelByUniqueName(task.uniqueName)).called(1);
      },
    );
  }

  test('late scheduling clamps the initial delay to zero', () async {
    final task = ClassSampleTask(
      slotId: 'slot',
      date: LocalDate(2026, 10, 5),
      offsetMinutes: 1,
      classStart: DateTime(2026, 10, 5, 7),
      runAt: now.subtract(const Duration(minutes: 1)),
    );
    await WorkmanagerClassSampleGateway(
      manager: manager,
      timeSource: Clock.fixed(now),
    ).schedule(task, ClassSampleSchedulePolicy.replace);
    verify(
      () => manager.registerOneOffTask(
        any(),
        any(),
        inputData: any(named: 'inputData'),
        initialDelay: Duration.zero,
        existingWorkPolicy: ExistingWorkPolicy.replace,
        constraints: any(named: 'constraints'),
      ),
    ).called(1);
  });

  test(
    'startup hook syncs geofences and schedules periodic and class work',
    () async {
      final source = occurrence();
      final geofences = FakeGeofenceRegistrar();
      final samples = FakeClassSampleGateway();
      final services = AppServices(
        database: createTestDatabase(),
        geofenceRegistrar: geofences,
        positionProvider: FakePositionProvider(
          PositionFix(position: source.place.center, timestamp: now),
        ),
        permissions: FakePermissions(),
        sampleTasks: samples,
        notifications: FakeNotifications(),
        timeSource: Clock.fixed(now),
      );
      addTearDown(services.dispose);
      await services.places.save(source.place);
      await services.courses.saveCourse(source.course);
      await services.courses.saveSlot(source.slot);
      await startBackgroundWork(
        services,
        scheduler: BackgroundScheduler(manager: manager),
      );
      expect(geofences.ids, hasLength(1));
      expect(samples.tasks, hasLength(2));
      verify(() => manager.initialize(callbackDispatcher)).called(1);
    },
  );

  test(
    'startup isolates registration failures and still schedules samples',
    () async {
      final source = occurrence();
      final geofences = FakeGeofenceRegistrar()..failSync = true;
      final samples = FakeClassSampleGateway();
      final errors = <Object>[];
      final services = AppServices(
        database: createTestDatabase(),
        geofenceRegistrar: geofences,
        positionProvider: FakePositionProvider(
          PositionFix(
            position: source.place.center,
            timestamp: now,
          ),
        ),
        permissions: FakePermissions(),
        sampleTasks: samples,
        notifications: FakeNotifications(),
        timeSource: Clock.fixed(now),
      );
      addTearDown(services.dispose);
      await services.places.save(source.place);
      await services.courses.saveCourse(source.course);
      await services.courses.saveSlot(source.slot);
      when(
        () => manager.initialize(any()),
      ).thenThrow(StateError('worker failed'));
      await startBackgroundWork(
        services,
        scheduler: BackgroundScheduler(manager: manager),
        onError: (error, _) => errors.add(error),
      );
      expect(errors, hasLength(2));
      expect(samples.tasks, hasLength(2));
    },
  );

  for (final status in LocationPermissionStatus.values.where(
    (status) => status != LocationPermissionStatus.always,
  )) {
    test(
      'startup defers location work for $status and registers periodic work',
      () async {
        final source = occurrence();
        final geofences = FakeGeofenceRegistrar();
        final samples = FakeClassSampleGateway();
        final errors = <Object>[];
        final services = AppServices(
          database: createTestDatabase(),
          geofenceRegistrar: geofences,
          positionProvider: FakePositionProvider(
            PositionFix(
              position: source.place.center,
              timestamp: now,
            ),
          ),
          permissions: FakePermissions(status),
          sampleTasks: samples,
          notifications: FakeNotifications(),
          timeSource: Clock.fixed(now),
        );
        addTearDown(services.dispose);
        await startBackgroundWork(
          services,
          scheduler: BackgroundScheduler(manager: manager),
          onError: (error, _) => errors.add(error),
        );
        expect(errors, isEmpty);
        expect(geofences.reads, 0);
        expect(samples.tasks, isEmpty);
        verify(() => manager.initialize(callbackDispatcher)).called(1);
      },
    );
  }
}
