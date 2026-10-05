import 'package:clock/clock.dart';
import 'package:did_i_assist/src/app/app_services.dart';
import 'package:did_i_assist/src/app/background_operations.dart';
import 'package:did_i_assist/src/domain/location/geofence_transition.dart';
import 'package:did_i_assist/src/domain/location/position_fix.dart';
import 'package:did_i_assist/src/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../data/database/test_database.dart';
import '../domain/services/fixtures.dart';
import 'fakes.dart';

final class _Listener extends Mock implements AttendanceResultListener {}

void main() {
  late AppServices services;
  late FakeGeofenceRegistrar geofences;
  late FakePositionProvider positions;
  late FakeClassSampleGateway tasks;
  late _Listener listener;
  late DateTime now;
  final source = occurrence();

  setUpAll(() => registerFallbackValue(<AttendanceRecord>[]));
  setUp(() {
    now = DateTime(2026, 10, 5, 9, 1);
    geofences = FakeGeofenceRegistrar();
    positions = FakePositionProvider(
      PositionFix(
        position: source.place.center,
        timestamp: now,
        accuracyMeters: 20,
      ),
    );
    tasks = FakeClassSampleGateway();
    listener = _Listener();
    when(() => listener.onAttendanceWritten(any())).thenAnswer((_) async {});
    var nextId = 0;
    services = AppServices(
      database: createTestDatabase(),
      geofenceRegistrar: geofences,
      positionProvider: positions,
      permissions: FakePermissions(),
      sampleTasks: tasks,
      timeSource: Clock(() => now),
      attendanceListeners: [listener],
      generateId: () => 'record-${nextId++}',
    );
  });
  tearDown(() => services.dispose());

  Future<void> seedSchedule() async {
    await services.places.save(source.place);
    await services.courses.saveCourse(source.course);
    await services.courses.saveSlot(source.slot);
  }

  test(
    'composition records geofence evidence, attendance and a learned trip',
    () async {
      await seedSchedule();
      await services.places.save(homePlace());
      await services.events.append(
        transition(
          LocationEventType.geofenceExit,
          DateTime(2026, 10, 5, 8, 30),
        ),
      );
      final result = await services.pipeline.onGeofenceTransition(
        GeofenceTransition(
          placeIds: [source.place.id],
          type: LocationEventType.geofenceEnter,
          receivedAt: DateTime(2026, 10, 5, 9),
        ),
      );
      expect(result.succeeded, isTrue);
      expect(result.events.single.placeId, source.place.id);
      expect(result.attendance.single.status, AttendanceStatus.present);
      expect(result.attendance.single.slotId, source.slot.id);
      expect(result.trips.single.duration, const Duration(minutes: 30));
      expect(
        await services.attendance.findBySlotAndDate(
          source.slot.id,
          source.occurrenceDate,
        ),
        result.attendance.single,
      );
      expect(
        await services.trips.getRecent(
          fromPlaceId: 'home',
          toPlaceId: source.place.id,
        ),
        result.trips,
      );
      verify(() => listener.onAttendanceWritten(result.attendance)).called(1);
    },
  );

  test(
    'periodic sync samples missing evidence and schedules tasks',
    () async {
      await seedSchedule();
      final result = await services.pipeline.onPeriodicTick();
      expect(result.succeeded, isTrue);
      expect(geofences.ids, hasLength(1));
      expect(positions.requests, 1);
      expect(result.attendance.single.status, AttendanceStatus.present);
      expect(tasks.tasks, hasLength(2));
      expect((await services.pipeline.onPeriodicTick()).succeeded, isTrue);
      expect(positions.requests, 1);
    },
  );

  test('no current class does not request a position', () async {
    await seedSchedule();
    now = DateTime(2026, 10, 5, 12);
    expect((await services.pipeline.onPeriodicTick()).succeeded, isTrue);
    expect(positions.requests, 0);
  });

  test(
    'class-time fallback recovers attendance without any geofence enter',
    () async {
      await seedSchedule();
      final result = await services.pipeline.onClassSampleTask(
        source.slot.id,
        source.occurrenceDate,
      );
      expect(result.succeeded, isTrue);
      expect(positions.requests, 1);
      expect(result.events.single.type, LocationEventType.positionSample);
      expect(result.attendance.single.status, AttendanceStatus.present);
    },
  );

  test('listener failure leaves evidence and attendance durable', () async {
    await seedSchedule();
    when(
      () => listener.onAttendanceWritten(any()),
    ).thenThrow(StateError('listener failed'));
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
  });

  test(
    'departure service shares the stored settings and schedule models',
    () async {
      await seedSchedule();
      await services.places.save(homePlace());
      expect(
        await services.departureService.adviseFor(
          source,
          currentPosition: source.place.center,
        ),
        isNotNull,
      );
      expect(await services.settings.load(), UserSettings());
      expect(await services.courses.getById(source.course.id), source.course);
    },
  );

  test('dispose closes the owned database and is idempotent', () async {
    await services.settings.load();
    final first = services.dispose();
    expect(services.dispose(), same(first));
    await first;
    await expectLater(services.settings.load(), throwsStateError);
  });
}
