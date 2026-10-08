import 'dart:async';

import 'package:did_i_attend/src/app/schedule_change_coordinator.dart';
import 'package:did_i_attend/src/domain/models/models.dart';
import 'package:did_i_attend/src/domain/repositories/course_repository.dart';
import 'package:did_i_attend/src/domain/repositories/place_repository.dart';
import 'package:did_i_attend/src/domain/repositories/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

final class _Places extends Mock implements PlaceRepository {}

final class _Courses extends Mock implements CourseRepository {}

final class _Settings extends Mock implements SettingsRepository {}

void main() {
  late StreamController<List<Place>> places;
  late StreamController<List<Course>> courses;
  late StreamController<List<ScheduleSlot>> slots;
  late StreamController<UserSettings> settings;
  late ScheduleChangeCoordinator coordinator;
  late List<String> calls;
  late List<Object> errors;
  late Completer<void>? blocked;
  late String? failed;

  void testCoordinator(
    String description,
    Future<void> Function(WidgetTester) body,
  ) {
    testWidgets(description, (tester) async {
      coordinator.start();
      await body(tester);
    });
  }

  setUp(() {
    places = StreamController.broadcast(sync: true);
    courses = StreamController.broadcast(sync: true);
    slots = StreamController.broadcast(sync: true);
    settings = StreamController.broadcast(sync: true);
    calls = [];
    errors = [];
    blocked = null;
    failed = null;
    final placeRepository = _Places();
    final courseRepository = _Courses();
    final settingsRepository = _Settings();
    when(placeRepository.watchAll).thenAnswer((_) => places.stream);
    when(courseRepository.watchAll).thenAnswer((_) => courses.stream);
    when(courseRepository.watchSlots).thenAnswer((_) => slots.stream);
    when(settingsRepository.watch).thenAnswer((_) => settings.stream);
    Future<void> action(String name) async {
      calls.add(name);
      if (name == failed) throw StateError('$name failed');
      if (name == 'samples') await blocked?.future;
    }

    coordinator = ScheduleChangeCoordinator(
      places: placeRepository,
      courses: courseRepository,
      settings: settingsRepository,
      syncGeofences: () => action('geofences'),
      syncClassSamples: () => action('samples'),
      reconcileReminders: () => action('reminders'),
      onError: (error, _) => errors.add(error),
    );
  });

  tearDown(() async {
    await coordinator.dispose();
    await Future.wait([
      places.close(),
      courses.close(),
      slots.close(),
      settings.close(),
    ]);
  });

  testCoordinator('bursts reset the debounce and synchronize once', (
    tester,
  ) async {
    places.add([]);
    await tester.pump(const Duration(milliseconds: 200));
    courses.add([]);
    slots.add([]);
    settings.add(UserSettings());
    await tester.pump(const Duration(milliseconds: 249));
    expect(calls, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, ['geofences', 'samples', 'reminders']);
  });

  for (final source in ['courses', 'slots', 'settings']) {
    testCoordinator('$source changes synchronize samples and reminders only', (
      tester,
    ) async {
      switch (source) {
        case 'courses':
          courses.add([]);
        case 'slots':
          slots.add([]);
        case 'settings':
          settings.add(UserSettings());
      }
      await tester.pump(const Duration(milliseconds: 250));
      expect(calls, ['samples', 'reminders']);
    });
  }

  testCoordinator('start is idempotent and repeated place changes coalesce', (
    tester,
  ) async {
    coordinator.start();
    places
      ..add([])
      ..add([]);
    await tester.pump(const Duration(milliseconds: 250));
    expect(calls, ['geofences', 'samples', 'reminders']);
  });

  testCoordinator('changes during a run wait and are not lost', (tester) async {
    blocked = Completer<void>();
    courses.add([]);
    await tester.pump(const Duration(milliseconds: 250));
    expect(calls, ['samples']);
    places.add([]);
    await tester.pump(const Duration(milliseconds: 250));
    expect(calls, ['samples']);
    blocked!.complete();
    blocked = null;
    await tester.pump();
    expect(calls, [
      'samples',
      'reminders',
      'geofences',
      'samples',
      'reminders',
    ]);
  });

  for (final stage in ['geofences', 'samples', 'reminders']) {
    testCoordinator('$stage failure is captured and later stages continue', (
      tester,
    ) async {
      failed = stage;
      places.add([]);
      await tester.pump(const Duration(milliseconds: 250));
      expect(calls, ['geofences', 'samples', 'reminders']);
      expect(errors, hasLength(1));
    });
  }

  testCoordinator(
    'stream errors are captured without terminating coordination',
    (
      tester,
    ) async {
      final error = StateError('watch failed');
      settings.addError(error, StackTrace.current);
      courses.add([]);
      await tester.pump(const Duration(milliseconds: 250));
      expect(errors, [error]);
      expect(calls, ['samples', 'reminders']);
    },
  );

  testCoordinator('dispose cancels subscriptions and pending debounce', (
    tester,
  ) async {
    places.add([]);
    await tester.runAsync(() async {
      final closing = coordinator.dispose();
      expect(coordinator.dispose(), same(closing));
      await closing;
    });
    expect(places.hasListener, isFalse);
    expect(courses.hasListener, isFalse);
    expect(slots.hasListener, isFalse);
    expect(settings.hasListener, isFalse);
    places.add([]);
    await tester.pump(const Duration(seconds: 1));
    expect(calls, isEmpty);
    expect(coordinator.start, throwsStateError);
  });

  testCoordinator(
    'dispose waits for in-flight work and skips remaining stages',
    (
      tester,
    ) async {
      blocked = Completer<void>();
      courses.add([]);
      await tester.pump(const Duration(milliseconds: 250));
      var closed = false;
      late Future<void> closing;
      await tester.runAsync(() async {
        closing = coordinator.dispose().then((_) => closed = true);
      });
      await tester.pump();
      expect(closed, isFalse);
      blocked!.complete();
      blocked = null;
      await tester.pump();
      await tester.runAsync(() => closing);
      expect(calls, ['samples']);
      expect(closed, isTrue);
    },
  );

  test(
    'flush explicitly handles pending changes without a timer wait',
    () async {
      coordinator.start();
      places.add([]);
      await coordinator.flush();
      expect(calls, ['geofences', 'samples', 'reminders']);
    },
  );

  test('negative debounce is rejected', () {
    expect(
      () => ScheduleChangeCoordinator(
        places: _Places(),
        courses: _Courses(),
        settings: _Settings(),
        syncGeofences: () async {},
        syncClassSamples: () async {},
        reconcileReminders: () async {},
        onError: (_, _) {},
        debounce: const Duration(milliseconds: -1),
      ),
      throwsArgumentError,
    );
  });

  test('partially started subscriptions remain disposable', () async {
    final placeRepository = _Places();
    final courseRepository = _Courses();
    when(placeRepository.watchAll).thenAnswer((_) => places.stream);
    when(courseRepository.watchAll).thenThrow(StateError('watch unavailable'));
    final partial = ScheduleChangeCoordinator(
      places: placeRepository,
      courses: courseRepository,
      settings: _Settings(),
      syncGeofences: () async {},
      syncClassSamples: () async {},
      reconcileReminders: () async {},
      onError: (_, _) {},
    );
    expect(partial.start, throwsStateError);
    expect(places.hasListener, isTrue);
    await partial.dispose();
    expect(places.hasListener, isFalse);
  });
}
