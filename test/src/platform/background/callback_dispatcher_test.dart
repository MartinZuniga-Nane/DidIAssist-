import 'dart:async';
import 'dart:ui';

import 'package:clock/clock.dart';
import 'package:did_i_attend/src/app/app_services.dart';
import 'package:did_i_attend/src/app/background_operations.dart';
import 'package:did_i_attend/src/core/local_date.dart';
import 'package:did_i_attend/src/domain/location/geofence_transition.dart';
import 'package:did_i_attend/src/domain/models/location_event_type.dart';
import 'package:did_i_attend/src/platform/background/background_geofence_callback.dart';
import 'package:did_i_attend/src/platform/background/background_task_names.dart';
import 'package:did_i_attend/src/platform/background/callback_dispatcher.dart';
import 'package:did_i_attend/src/platform/background_location_callback.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:workmanager/workmanager.dart';

import '../fixtures.dart';

final class _Target extends Mock implements BackgroundTaskTarget {}

final class _Services implements BackgroundTaskServices {
  _Services(this.pipeline);
  @override
  final BackgroundTaskTarget pipeline;
  @override
  final timeSource = Clock.fixed(DateTime.utc(2026, 10, 5, 9));
  int closes = 0;
  bool failClosing = false;
  @override
  Future<void> dispose() async {
    closes++;
    if (failClosing) throw StateError('close failed');
  }
}

void main() {
  late _Target target;
  late _Services services;
  late int opens;

  Future<BackgroundTaskServices> open() async {
    opens++;
    return services;
  }

  setUpAll(() {
    registerFallbackValue(LocalDate(2026, 10, 5));
    registerFallbackValue(
      GeofenceTransition(
        placeIds: const ['campus'],
        type: LocationEventType.geofenceEnter,
        receivedAt: DateTime.utc(2026),
      ),
    );
  });
  setUp(() {
    opens = 0;
    target = _Target();
    services = _Services(target);
    when(target.onPeriodicTick).thenAnswer((_) async => BackgroundResult());
    when(
      () => target.onClassSampleTask(any(), any()),
    ).thenAnswer((_) async => BackgroundResult());
    when(() => target.handle(any())).thenAnswer((_) async {});
  });
  tearDown(BackgroundLocationRegistry.clear);

  test('entry points have native callback handles', () {
    expect(PluginUtilities.getCallbackHandle(callbackDispatcher), isNotNull);
    expect(
      PluginUtilities.getCallbackHandle(backgroundGeofenceCallback),
      isNotNull,
    );
  });

  for (final task in [
    BackgroundTaskNames.periodic,
    Workmanager.iOSBackgroundTask,
  ]) {
    test('$task routes to periodic evaluation and closes services', () async {
      expect(
        await dispatchBackgroundTask(task, null, openServices: open),
        isTrue,
      );
      verify(target.onPeriodicTick).called(1);
      expect(opens, 1);
      expect(services.closes, 1);
    });
  }

  test('class task routes its slot ID and local date', () async {
    expect(
      await dispatchBackgroundTask(BackgroundTaskNames.classSample, {
        'slotId': 'slot',
        'date': '2026-10-05',
        'offsetMinutes': 1,
      }, openServices: open),
      isTrue,
    );
    verify(
      () => target.onClassSampleTask('slot', LocalDate(2026, 10, 5)),
    ).called(1);
    expect(services.closes, 1);
  });

  test('unknown tasks and missing payload do not open the database', () async {
    expect(
      await dispatchBackgroundTask('unrelated', null, openServices: open),
      isTrue,
    );
    expect(
      await dispatchBackgroundTask(
        BackgroundTaskNames.classSample,
        null,
        openServices: open,
      ),
      isTrue,
    );
    expect(
      await dispatchBackgroundTask(BackgroundTaskNames.classSample, {
        'slotId': '',
        'date': '2026-10-05',
      }, openServices: open),
      isTrue,
    );
    expect(opens, 0);
  });

  test('invalid dates do not open services', () async {
    expect(
      await dispatchBackgroundTask(BackgroundTaskNames.classSample, {
        'slotId': 'slot',
        'date': '2026-02-30',
      }, openServices: open),
      isFalse,
    );
    expect(opens, 0);
  });

  test('pipeline failures request retry and still close services', () async {
    when(target.onPeriodicTick).thenAnswer(
      (_) async => BackgroundResult(
        failures: [
          BackgroundStageFailure(
            BackgroundStage.evaluateAttendance,
            StateError('failed'),
            StackTrace.current,
          ),
        ],
      ),
    );
    expect(
      await dispatchBackgroundTask(
        BackgroundTaskNames.periodic,
        null,
        openServices: open,
      ),
      isFalse,
    );
    expect(services.closes, 1);
  });

  test(
    'thrown task and cleanup errors both fail while attempting disposal',
    () async {
      when(target.onPeriodicTick).thenThrow(StateError('task failed'));
      expect(
        await dispatchBackgroundTask(
          BackgroundTaskNames.periodic,
          null,
          openServices: open,
        ),
        isFalse,
      );
      expect(services.closes, 1);
      when(target.onPeriodicTick).thenAnswer((_) async => BackgroundResult());
      services.failClosing = true;
      expect(
        await dispatchBackgroundTask(
          BackgroundTaskNames.periodic,
          null,
          openServices: open,
        ),
        isFalse,
      );
      expect(services.closes, 2);
    },
  );

  test(
    'opening failures request retry without attempting unavailable disposal',
    () async {
      expect(
        await dispatchBackgroundTask(
          BackgroundTaskNames.periodic,
          null,
          openServices: () async => throw StateError('open failed'),
        ),
        isFalse,
      );
      expect(services.closes, 0);
    },
  );

  test('native bootstrap registers locally, delegates and disposes', () async {
    when(() => target.handle(any())).thenAnswer((_) async {
      expect(BackgroundLocationRegistry.isRegistered, isTrue);
      expect(services.closes, 0);
    });
    await dispatchBackgroundGeofence(callbackParams(), openServices: open);
    final transition =
        verify(() => target.handle(captureAny())).captured.single
            as GeofenceTransition;
    expect(transition.receivedAt, services.timeSource.now());
    expect(BackgroundLocationRegistry.isRegistered, isFalse);
    expect(services.closes, 1);
  });

  test('native bootstrap clears and closes after a handler failure', () async {
    when(() => target.handle(any())).thenThrow(StateError('storage failed'));
    await expectLater(
      dispatchBackgroundGeofence(callbackParams(), openServices: open),
      throwsStateError,
    );
    expect(BackgroundLocationRegistry.isRegistered, isFalse);
    expect(services.closes, 1);
    when(() => target.handle(any())).thenAnswer((_) async {});
    await dispatchBackgroundGeofence(callbackParams(), openServices: open);
    expect(services.closes, 2);
  });

  test(
    'overlapping native callbacks cannot replace an active registry handler',
    () async {
      final completed = Completer<void>();
      when(() => target.handle(any())).thenAnswer((_) => completed.future);
      final first = dispatchBackgroundGeofence(
        callbackParams(),
        openServices: open,
      );
      final second = dispatchBackgroundGeofence(
        callbackParams(),
        openServices: open,
      );
      await Future<void>.delayed(Duration.zero);
      expect(opens, 1);
      completed.complete();
      await Future.wait([first, second]);
      expect(opens, 2);
      expect(services.closes, 2);
      expect(BackgroundLocationRegistry.isRegistered, isFalse);
    },
  );
}
