import 'package:clock/clock.dart';
import 'package:did_i_assist/src/core/local_date.dart';
import 'package:did_i_assist/src/domain/models/models.dart';
import 'package:did_i_assist/src/domain/repositories/attendance_repository.dart';
import 'package:did_i_assist/src/domain/repositories/course_repository.dart';
import 'package:did_i_assist/src/domain/repositories/location_event_repository.dart';
import 'package:did_i_assist/src/domain/repositories/place_repository.dart';
import 'package:did_i_assist/src/domain/repositories/settings_repository.dart';
import 'package:did_i_assist/src/domain/services/attendance_evaluator.dart';
import 'package:did_i_assist/src/domain/services/attendance_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../models/fixtures.dart' as fixtures;

final class _MockCourseRepository extends Mock implements CourseRepository {}

final class _MockPlaceRepository extends Mock implements PlaceRepository {}

final class _MockAttendanceRepository extends Mock
    implements AttendanceRepository {}

final class _MockLocationEventRepository extends Mock
    implements LocationEventRepository {}

final class _MockSettingsRepository extends Mock
    implements SettingsRepository {}

void main() {
  late _MockCourseRepository courses;
  late _MockPlaceRepository places;
  late _MockAttendanceRepository attendance;
  late _MockLocationEventRepository locationEvents;
  late _MockSettingsRepository settings;
  late List<Course> courseData;
  late List<ScheduleSlot> slotData;
  late List<Place> placeData;
  late List<LocationEvent> eventData;
  late UserSettings settingsData;
  late Map<(String, LocalDate), AttendanceRecord> storedRecords;
  late ClassOccurrence occurrence;
  late DateTime now;
  late int generatedIds;
  late int clockReads;

  setUpAll(() {
    registerFallbackValue(DateTime(2026, 10, 5));
    registerFallbackValue(LocalDate(2026, 10, 5));
    registerFallbackValue(fixtures.sampleAttendance());
  });

  setUp(() {
    courses = _MockCourseRepository();
    places = _MockPlaceRepository();
    attendance = _MockAttendanceRepository();
    locationEvents = _MockLocationEventRepository();
    settings = _MockSettingsRepository();
    courseData = [fixtures.sampleCourse()];
    slotData = [fixtures.sampleSlot()];
    placeData = [fixtures.samplePlace()];
    eventData = [];
    settingsData = UserSettings();
    storedRecords = {};
    occurrence = fixtures.sampleOccurrence();
    now = occurrence.end;
    generatedIds = 0;
    clockReads = 0;

    when(() => courses.getAll()).thenAnswer((_) async => courseData);
    when(() => courses.getSlots()).thenAnswer((_) async => slotData);
    when(() => courses.getById(any())).thenAnswer((invocation) async {
      final id = invocation.positionalArguments.single as String;
      for (final course in courseData) {
        if (course.id == id) return course;
      }
      return null;
    });
    when(() => places.getAll()).thenAnswer((_) async => placeData);
    when(() => settings.load()).thenAnswer((_) async => settingsData);
    when(
      () => locationEvents.query(
        from: any(named: 'from'),
        until: any(named: 'until'),
        placeId: any(named: 'placeId'),
      ),
    ).thenAnswer((_) async => eventData);
    when(() => attendance.findBySlotAndDate(any(), any())).thenAnswer(
      (invocation) async =>
          storedRecords[(
            invocation.positionalArguments[0] as String,
            invocation.positionalArguments[1] as LocalDate,
          )],
    );
    when(() => attendance.upsert(any())).thenAnswer((invocation) async {
      final candidate =
          invocation.positionalArguments.single as AttendanceRecord;
      final key = (candidate.slotId, candidate.occurrenceDate);
      final existing = storedRecords[key];
      if (existing?.source == AttendanceSource.manual &&
          candidate.source == AttendanceSource.automatic) {
        return existing!;
      }
      final stored = candidate.copyWith(id: existing?.id ?? candidate.id);
      storedRecords[key] = stored;
      return stored;
    });
  });

  AttendanceService service({
    AttendanceEvaluator? evaluator,
    bool useDefaultId = false,
  }) => AttendanceService(
    courseRepository: courses,
    placeRepository: places,
    attendanceRepository: attendance,
    locationEventRepository: locationEvents,
    settingsRepository: settings,
    timeSource: Clock(() {
      clockReads++;
      return now;
    }),
    idGenerator: useDefaultId
        ? null
        : () {
            generatedIds++;
            return '00000000-0000-4000-8000-'
                '${generatedIds.toString().padLeft(12, '0')}';
          },
    evaluator: evaluator,
  );

  LocationEvent enter(DateTime at) => LocationEvent(
    id: fixtures.recordId,
    type: LocationEventType.geofenceEnter,
    placeId: fixtures.placeId,
    recordedAt: at,
  );

  AttendanceRecord record({
    required AttendanceStatus status,
    AttendanceSource source = AttendanceSource.automatic,
    DateTime? checkInAt,
  }) => AttendanceRecord(
    id: fixtures.recordId,
    slotId: occurrence.slot.id,
    courseId: occurrence.course.id,
    occurrenceDate: occurrence.occurrenceDate,
    status: status,
    source: source,
    checkInAt: checkInAt,
    evaluatedAt: occurrence.end.toUtc().subtract(const Duration(minutes: 1)),
  );

  void store(AttendanceRecord value) {
    storedRecords[(value.slotId, value.occurrenceDate)] = value;
  }

  group('evaluateRecent', () {
    test('writes automatic absence using a single clock snapshot', () async {
      final written = await service().evaluateRecent();
      expect(written, hasLength(1));
      final value = written.single;
      expect(value.status, AttendanceStatus.absent);
      expect(value.source, AttendanceSource.automatic);
      expect(value.slotId, occurrence.slot.id);
      expect(value.courseId, occurrence.course.id);
      expect(value.occurrenceDate, occurrence.occurrenceDate);
      expect(value.evaluatedAt, now.toUtc());
      expect(value.evaluatedAt.isUtc, isTrue);
      expect(value.checkInAt, isNull);
      expect(generatedIds, 1);
      expect(clockReads, 1);
    });

    test('does not persist pending classes or generate IDs for them', () async {
      now = occurrence.start;
      expect(await service().evaluateRecent(), isEmpty);
      verifyNever(() => attendance.upsert(any()));
      expect(generatedIds, 0);
    });

    for (final status in AttendanceStatus.values) {
      test(
        'never overwrites an existing manual ${status.name} record',
        () async {
          final existing = record(
            status: status,
            source: AttendanceSource.manual,
          );
          store(existing);
          expect(await service().evaluateRecent(), isEmpty);
          expect(storedRecords.values.single, existing);
          verifyNever(() => attendance.upsert(any()));
          verifyNever(
            () => locationEvents.query(
              from: any(named: 'from'),
              until: any(named: 'until'),
              placeId: any(named: 'placeId'),
            ),
          );
          expect(generatedIds, 0);
        },
      );
    }

    test('avoids churn when absence and check-in are unchanged', () async {
      final existing = record(status: AttendanceStatus.absent);
      store(existing);
      expect(await service().evaluateRecent(), isEmpty);
      expect(storedRecords.values.single.evaluatedAt, existing.evaluatedAt);
      verifyNever(() => attendance.upsert(any()));
      expect(generatedIds, 0);
    });

    test('avoids churn when presence and check-in are unchanged', () async {
      final existing = record(
        status: AttendanceStatus.present,
        checkInAt: occurrence.start,
      );
      store(existing);
      eventData = [enter(occurrence.start)];
      expect(await service().evaluateRecent(), isEmpty);
      verifyNever(() => attendance.upsert(any()));
      expect(storedRecords.values.single, existing);
    });

    test(
      'updates a changed status while preserving the existing record ID',
      () async {
        store(
          record(
            status: AttendanceStatus.late,
            checkInAt: occurrence.start,
          ),
        );
        eventData = [enter(occurrence.start)];
        final written = await service().evaluateRecent();
        expect(written.single.status, AttendanceStatus.present);
        expect(written.single.id, fixtures.recordId);
        expect(generatedIds, 0);
      },
    );

    test(
      'updates a changed check-in even when the status is unchanged',
      () async {
        store(
          record(
            status: AttendanceStatus.present,
            checkInAt: occurrence.start.add(const Duration(minutes: 1)),
          ),
        );
        eventData = [enter(occurrence.start)];
        final written = await service().evaluateRecent();
        expect(written.single.checkInAt, occurrence.start.toUtc());
        expect(written.single.id, fixtures.recordId);
        expect(generatedIds, 0);
      },
    );

    test(
      'corrects absence after delayed evidence and is idempotent afterward',
      () async {
        final engine = service();
        final first = (await engine.evaluateRecent()).single;
        expect(first.status, AttendanceStatus.absent);
        eventData = [enter(occurrence.start)];
        now = occurrence.end.add(const Duration(minutes: 10));
        final correction = (await engine.evaluateRecent()).single;
        expect(correction.status, AttendanceStatus.present);
        expect(correction.id, first.id);
        expect(correction.checkInAt, occurrence.start.toUtc());
        expect(await engine.evaluateRecent(), isEmpty);
        verify(() => attendance.upsert(any())).called(2);
        expect(generatedIds, 1);
      },
    );

    test(
      'delayed outside evidence can correct a carried presence to absence',
      () async {
        final window = occurrence.start.subtract(const Duration(minutes: 15));
        eventData = [enter(window.subtract(const Duration(minutes: 2)))];
        final engine = service();
        final first = (await engine.evaluateRecent()).single;
        expect(first.status, AttendanceStatus.present);
        eventData.add(
          LocationEvent(
            id: fixtures.homeId,
            type: LocationEventType.positionSample,
            position: fixtures.samplePoint().copyWith(
              latitude: 51.5007,
              longitude: -0.1246,
            ),
            recordedAt: window.subtract(const Duration(minutes: 1)),
          ),
        );
        final correction = (await engine.evaluateRecent()).single;
        expect(correction.id, first.id);
        expect(correction.status, AttendanceStatus.absent);
        expect(correction.checkInAt, isNull);
        expect(eventData, hasLength(2));
        expect(await engine.evaluateRecent(), isEmpty);
      },
    );

    test(
      'does not report a racing manual edit as an automatic write',
      () async {
        final manual = record(
          status: AttendanceStatus.excused,
          source: AttendanceSource.manual,
        );
        when(() => attendance.upsert(any())).thenAnswer((_) async => manual);
        expect(await service().evaluateRecent(), isEmpty);
        final attempted =
            verify(
                  () => attendance.upsert(captureAny()),
                ).captured.single
                as AttendanceRecord;
        expect(attempted.source, AttendanceSource.automatic);
      },
    );

    test(
      'returns the canonical automatic record stored by a racing upsert',
      () async {
        when(() => attendance.upsert(any())).thenAnswer((invocation) async {
          final candidate =
              invocation.positionalArguments.single as AttendanceRecord;
          return candidate.copyWith(id: fixtures.homeId);
        });
        final written = await service().evaluateRecent();
        expect(written.single.id, fixtures.homeId);
        expect(written.single.source, AttendanceSource.automatic);
        expect(written.single.status, AttendanceStatus.absent);
      },
    );

    test(
      'uses settings policy and the evaluator carry-over for event queries',
      () async {
        settingsData = UserSettings(
          attendancePolicy: AttendancePolicy(
            earlyWindowMinutes: 20,
            graceMinutes: 0,
          ),
        );
        eventData = [enter(occurrence.start.add(const Duration(minutes: 5)))];
        final written = await service(
          evaluator: AttendanceEvaluator(carryOver: const Duration(hours: 6)),
        ).evaluateRecent();
        expect(written.single.status, AttendanceStatus.late);
        verify(
          () => locationEvents.query(
            from: occurrence.start.toUtc().subtract(
              const Duration(hours: 6, minutes: 20),
            ),
            until: occurrence.end.toUtc().add(const Duration(microseconds: 1)),
            placeId: occurrence.place.id,
          ),
        ).called(1);
      },
    );

    test('uses the accuracy limit loaded from settings', () async {
      settingsData = UserSettings(
        attendancePolicy: AttendancePolicy(maxAccuracyMeters: 20),
      );
      eventData = [
        LocationEvent(
          id: fixtures.recordId,
          type: LocationEventType.positionSample,
          position: fixtures.samplePoint(),
          accuracyMeters: 30,
          recordedAt: occurrence.start,
        ),
      ];
      expect(
        (await service().evaluateRecent()).single.status,
        AttendanceStatus.absent,
      );
    });

    test(
      'writes an ongoing arrival after the configured late cutoff as absent',
      () async {
        settingsData = UserSettings(
          attendancePolicy: AttendancePolicy(
            graceMinutes: 0,
            lateUntilMinutes: 5,
          ),
        );
        now = occurrence.start.add(const Duration(minutes: 7));
        final arrival = occurrence.start.add(const Duration(minutes: 6));
        eventData = [enter(arrival)];
        final written = (await service().evaluateRecent()).single;
        expect(written.status, AttendanceStatus.absent);
        expect(written.checkInAt, arrival.toUtc());
      },
    );

    test(
      'default lookback includes starts exactly 48 hours ago and now',
      () async {
        now = DateTime(2026, 10, 7, 9);
        slotData = [
          occurrence.slot.copyWith(id: fixtures.homeId, startMinute: 539),
          occurrence.slot,
          occurrence.slot.copyWith(
            id: fixtures.courseId,
            weekday: DateTime.wednesday,
          ),
          occurrence.slot.copyWith(
            id: fixtures.recordId,
            weekday: DateTime.wednesday,
            startMinute: 541,
          ),
        ];
        eventData = [enter(DateTime(2026, 10, 5, 9)), enter(now)];
        final written = await service().evaluateRecent();
        expect(written.map((value) => value.slotId), [
          occurrence.slot.id,
          fixtures.courseId,
        ]);
        expect(written.map((value) => value.occurrenceDate), [
          LocalDate(2026, 10, 5),
          LocalDate(2026, 10, 7),
        ]);
        expect(
          written.every(
            (value) => value.status == AttendanceStatus.present,
          ),
          isTrue,
        );
      },
    );

    test(
      'custom lookback excludes earlier starts and includes its lower bound',
      () async {
        slotData = [
          occurrence.slot.copyWith(id: fixtures.homeId, startMinute: 449),
          occurrence.slot.copyWith(id: fixtures.courseId, startMinute: 450),
          occurrence.slot,
        ];
        final written = await service().evaluateRecent(
          lookback: const Duration(hours: 3),
        );
        expect(written.map((value) => value.slotId), [
          fixtures.courseId,
          occurrence.slot.id,
        ]);
      },
    );

    test('zero lookback evaluates only a class starting exactly now', () async {
      now = occurrence.start;
      eventData = [enter(now)];
      slotData.add(
        occurrence.slot.copyWith(
          id: fixtures.homeId,
          startMinute: occurrence.slot.startMinute - 1,
        ),
      );
      expect(
        (await service().evaluateRecent(lookback: Duration.zero)).single.slotId,
        occurrence.slot.id,
      );
    });

    test(
      'rejects negative lookback before reading time or repositories',
      () async {
        await expectLater(
          service().evaluateRecent(lookback: const Duration(microseconds: -1)),
          throwsArgumentError,
        );
        verifyNever(() => settings.load());
        verifyNever(() => courses.getAll());
        expect(clockReads, 0);
      },
    );

    test(
      'loads each repository snapshot once for multiple occurrences',
      () async {
        slotData.add(
          occurrence.slot.copyWith(
            id: fixtures.homeId,
            startMinute: 480,
          ),
        );
        expect(await service().evaluateRecent(), hasLength(2));
        verify(() => courses.getAll()).called(1);
        verify(() => courses.getSlots()).called(1);
        verify(() => places.getAll()).called(1);
        verify(() => settings.load()).called(1);
        expect(clockReads, 1);
      },
    );

    test(
      'keeps one time snapshot when asynchronous repository work takes time',
      () async {
        final snapshot = now;
        when(() => settings.load()).thenAnswer((_) async {
          now = now.add(const Duration(hours: 1));
          return settingsData;
        });
        slotData.add(
          occurrence.slot.copyWith(
            id: fixtures.homeId,
            startMinute: 645,
          ),
        );
        final written = await service().evaluateRecent();
        expect(written, hasLength(1));
        expect(written.single.evaluatedAt, snapshot.toUtc());
        expect(clockReads, 1);
      },
    );

    test(
      'bounds event queries at now and ignores returned future events',
      () async {
        now = occurrence.start.add(const Duration(minutes: 10));
        eventData = [
          enter(now.add(const Duration(microseconds: 1))),
          enter(now),
        ];
        final written = await service().evaluateRecent();
        expect(written.single.status, AttendanceStatus.present);
        expect(written.single.checkInAt, now.toUtc());
        verify(
          () => locationEvents.query(
            from: occurrence.start.toUtc().subtract(
              const Duration(hours: 12, minutes: 15),
            ),
            until: now.toUtc().add(const Duration(microseconds: 1)),
            placeId: occurrence.place.id,
          ),
        ).called(1);
      },
    );

    test(
      'includes class-end evidence and bounds queries at end plus epsilon',
      () async {
        now = occurrence.end.add(const Duration(hours: 1));
        eventData = [
          enter(occurrence.end.add(const Duration(microseconds: 1))),
          enter(occurrence.end),
        ];
        final written = await service().evaluateRecent();
        expect(written.single.status, AttendanceStatus.late);
        expect(written.single.checkInAt, occurrence.end.toUtc());
        verify(
          () => locationEvents.query(
            from: occurrence.start.toUtc().subtract(
              const Duration(hours: 12, minutes: 15),
            ),
            until: occurrence.end.toUtc().add(const Duration(microseconds: 1)),
            placeId: occurrence.place.id,
          ),
        ).called(1);
      },
    );

    test(
      'keeps an overnight occurrence date on its starting local day',
      () async {
        slotData = [occurrence.slot.copyWith(startMinute: 1410)];
        now = DateTime(2026, 10, 6, 1);
        eventData = [enter(DateTime(2026, 10, 6, 0, 1))];
        final written = (await service().evaluateRecent()).single;
        expect(written.occurrenceDate, LocalDate(2026, 10, 5));
        expect(written.status, AttendanceStatus.late);
        expect(written.checkInAt, DateTime(2026, 10, 6, 0, 1).toUtc());
      },
    );

    test('returns no writes for missing course or place references', () async {
      courseData = [];
      expect(await service().evaluateRecent(), isEmpty);
      verifyNever(() => attendance.upsert(any()));
      courseData = [fixtures.sampleCourse()];
      placeData = [];
      expect(await service().evaluateRecent(), isEmpty);
      verifyNever(() => attendance.upsert(any()));
    });

    test(
      'repository failures propagate instead of claiming successful writes',
      () async {
        when(
          () => attendance.upsert(any()),
        ).thenThrow(StateError('Unavailable'));
        await expectLater(service().evaluateRecent(), throwsStateError);
      },
    );

    test('uses UUID v4 when no ID generator is injected', () async {
      final written = (await service(
        useDefaultId: true,
      ).evaluateRecent()).single;
      expect(
        written.id,
        matches(
          '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-'
          r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      );
      expect(generatedIds, 0);
    });

    test('uses the scoped Clock when no clock is injected', () async {
      final fixed = DateTime(2026, 10, 5, 12);
      final engine = withClock(
        Clock.fixed(fixed),
        () => AttendanceService(
          courseRepository: courses,
          placeRepository: places,
          attendanceRepository: attendance,
          locationEventRepository: locationEvents,
          settingsRepository: settings,
          idGenerator: () => fixtures.recordId,
        ),
      );
      expect((await engine.evaluateRecent()).single.evaluatedAt, fixed.toUtc());
    });
  });

  group('markManually', () {
    test('rejects pending before reading time or repositories', () async {
      final existing = record(
        status: AttendanceStatus.excused,
        source: AttendanceSource.manual,
      );
      store(existing);
      await expectLater(
        service().markManually(
          occurrence.slot.id,
          occurrence.occurrenceDate,
          AttendanceStatus.pending,
        ),
        throwsArgumentError,
      );
      verifyNever(() => courses.getSlots());
      verifyNever(() => courses.getById(any()));
      verifyNever(() => attendance.findBySlotAndDate(any(), any()));
      verifyNever(() => attendance.upsert(any()));
      expect(storedRecords.values.single, existing);
      expect(generatedIds, 0);
      expect(clockReads, 0);
    });

    test('missing slot fails without generating an ID or writing', () async {
      await expectLater(
        service().markManually(
          fixtures.homeId,
          occurrence.occurrenceDate,
          AttendanceStatus.excused,
        ),
        throwsArgumentError,
      );
      verifyNever(() => attendance.findBySlotAndDate(any(), any()));
      verifyNever(() => attendance.upsert(any()));
      expect(generatedIds, 0);
    });

    test(
      'rejects a date on a different weekday before loading the course',
      () async {
        await expectLater(
          service().markManually(
            occurrence.slot.id,
            LocalDate(2026, 10, 4),
            AttendanceStatus.excused,
          ),
          throwsArgumentError,
        );
        verifyNever(() => courses.getById(any()));
        verifyNever(() => attendance.findBySlotAndDate(any(), any()));
        verifyNever(() => attendance.upsert(any()));
        expect(generatedIds, 0);
      },
    );

    test('rejects a slot whose course does not exist', () async {
      courseData = [];
      await expectLater(
        service().markManually(
          occurrence.slot.id,
          occurrence.occurrenceDate,
          AttendanceStatus.absent,
        ),
        throwsArgumentError,
      );
      verify(() => courses.getById(occurrence.slot.courseId)).called(1);
      verifyNever(() => attendance.findBySlotAndDate(any(), any()));
      verifyNever(() => attendance.upsert(any()));
      expect(generatedIds, 0);
    });

    for (final bounds in [
      (
        name: 'before the semester begins',
        course: fixtures.sampleCourse().copyWith(
          activeFrom: () => LocalDate(2026, 10, 12),
        ),
      ),
      (
        name: 'after the semester ends',
        course: fixtures.sampleCourse().copyWith(
          activeUntil: () => LocalDate(2026, 9, 28),
        ),
      ),
    ]) {
      test('rejects a matching weekday ${bounds.name}', () async {
        courseData = [bounds.course];
        await expectLater(
          service().markManually(
            occurrence.slot.id,
            occurrence.occurrenceDate,
            AttendanceStatus.present,
          ),
          throwsArgumentError,
        );
        verify(() => courses.getById(occurrence.slot.courseId)).called(1);
        verifyNever(() => attendance.findBySlotAndDate(any(), any()));
        verifyNever(() => attendance.upsert(any()));
        expect(generatedIds, 0);
      });
    }

    for (final date in [LocalDate(2026, 10, 5), LocalDate(2026, 10, 12)]) {
      test('accepts inclusive semester boundary day ${date.day}', () async {
        courseData = [
          fixtures.sampleCourse().copyWith(
            activeFrom: () => LocalDate(2026, 10, 5),
            activeUntil: () => LocalDate(2026, 10, 12),
          ),
        ];
        final written = await service().markManually(
          occurrence.slot.id,
          date,
          AttendanceStatus.late,
        );
        expect(written.occurrenceDate, date);
        expect(written.status, AttendanceStatus.late);
        expect(written.source, AttendanceSource.manual);
        verify(() => courses.getById(occurrence.slot.courseId)).called(1);
        verifyNever(() => courses.getAll());
      });
    }

    test(
      'writes an excused manual record using the slot course and local date',
      () async {
        slotData = [occurrence.slot.copyWith(courseId: fixtures.homeId)];
        courseData = [fixtures.sampleCourse().copyWith(id: fixtures.homeId)];
        final date = occurrence.occurrenceDate;
        final written = await service().markManually(
          occurrence.slot.id,
          date,
          AttendanceStatus.excused,
        );
        expect(written.source, AttendanceSource.manual);
        expect(written.status, AttendanceStatus.excused);
        expect(written.courseId, fixtures.homeId);
        expect(written.occurrenceDate, date);
        expect(written.checkInAt, isNull);
        expect(written.evaluatedAt, now.toUtc());
        verify(() => courses.getSlots()).called(1);
        verify(() => courses.getById(fixtures.homeId)).called(1);
        verifyNever(() => courses.getAll());
        verifyNever(() => places.getAll());
        verifyNever(() => settings.load());
      },
    );

    test('manual overrides retain the existing ID and check-in', () async {
      final existing = record(
        status: AttendanceStatus.present,
        checkInAt: occurrence.start,
      );
      store(existing);
      final written = await service().markManually(
        occurrence.slot.id,
        occurrence.occurrenceDate,
        AttendanceStatus.excused,
      );
      expect(written.id, existing.id);
      expect(written.checkInAt, existing.checkInAt);
      expect(written.source, AttendanceSource.manual);
      expect(written.status, AttendanceStatus.excused);
      expect(generatedIds, 0);
    });

    for (final status in [
      AttendanceStatus.present,
      AttendanceStatus.late,
      AttendanceStatus.absent,
      AttendanceStatus.excused,
    ]) {
      test('allows an explicit manual ${status.name} decision', () async {
        final existing = record(
          status: AttendanceStatus.excused,
          source: AttendanceSource.manual,
        );
        store(existing);
        final written = await service().markManually(
          occurrence.slot.id,
          occurrence.occurrenceDate,
          status,
        );
        expect(written.status, status);
        expect(written.source, AttendanceSource.manual);
        expect(written.id, existing.id);
        expect(generatedIds, 0);
      });
    }
  });
}
