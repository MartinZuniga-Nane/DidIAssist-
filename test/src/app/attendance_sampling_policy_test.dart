import 'package:clock/clock.dart';
import 'package:did_i_attend/src/app/attendance_sampling_policy.dart';
import 'package:did_i_attend/src/domain/models/models.dart';
import 'package:did_i_attend/src/domain/repositories/course_repository.dart';
import 'package:did_i_attend/src/domain/repositories/location_event_repository.dart';
import 'package:did_i_attend/src/domain/repositories/place_repository.dart';
import 'package:did_i_attend/src/domain/repositories/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../domain/services/fixtures.dart';

final class _Courses extends Mock implements CourseRepository {}

final class _Places extends Mock implements PlaceRepository {}

final class _Events extends Mock implements LocationEventRepository {}

final class _Settings extends Mock implements SettingsRepository {}

void main() {
  late _Courses courses;
  late _Places places;
  late _Events events;
  late _Settings settings;
  late AttendanceSamplingPolicy sampling;
  late DateTime now;
  late List<LocationEvent> evidence;
  final source = occurrence();

  setUpAll(() => registerFallbackValue(DateTime.utc(2026)));
  setUp(() {
    now = DateTime(2026, 10, 5, 9, 1);
    evidence = [];
    courses = _Courses();
    places = _Places();
    events = _Events();
    settings = _Settings();
    when(courses.getAll).thenAnswer((_) async => [source.course]);
    when(() => courses.getSlots()).thenAnswer((_) async => [source.slot]);
    when(places.getAll).thenAnswer((_) async => [source.place]);
    when(settings.load).thenAnswer((_) async => UserSettings());
    when(
      () => events.query(
        from: any(named: 'from'),
        until: any(named: 'until'),
        placeId: any(named: 'placeId'),
      ),
    ).thenAnswer((_) async => evidence);
    sampling = AttendanceSamplingPolicy(
      courses: courses,
      places: places,
      events: events,
      settings: settings,
      timeSource: Clock(() => now),
    );
  });

  test('current attendance window without evidence needs GPS', () async {
    expect(await sampling.needsSample(), isTrue);
  });
  for (final type in [
    LocationEventType.geofenceEnter,
    LocationEventType.geofenceDwell,
  ]) {
    test('${type.name} inside the window avoids GPS', () async {
      evidence = [transition(type, source.start, placeId: source.place.id)];
      expect(await sampling.needsSample(), isFalse);
    });
  }
  test(
    'accurate position evidence avoids GPS regardless of place ID',
    () async {
      evidence = [
        LocationEvent(
          id: 'sample',
          type: LocationEventType.positionSample,
          placeId: 'unrelated',
          position: source.place.center,
          accuracyMeters: 20,
          recordedAt: source.start,
        ),
      ];
      expect(await sampling.needsSample(), isFalse);
    },
  );
  test('inaccurate and outside samples still need GPS', () async {
    evidence = [
      LocationEvent(
        id: 'sample',
        type: LocationEventType.positionSample,
        position: source.place.center,
        accuracyMeters: 201,
        recordedAt: source.start,
      ),
    ];
    expect(await sampling.needsSample(), isTrue);
    evidence = [
      LocationEvent(
        id: 'outside',
        type: LocationEventType.positionSample,
        position: bigBen(),
        recordedAt: source.start,
      ),
    ];
    expect(await sampling.needsSample(), isTrue);
  });
  test('confirmed carry-over inside evidence avoids GPS', () async {
    evidence = [
      transition(
        LocationEventType.geofenceEnter,
        DateTime(2026, 10, 5, 8),
        placeId: source.place.id,
      ),
    ];
    expect(await sampling.needsSample(), isFalse);
    evidence.add(
      transition(
        LocationEventType.geofenceExit,
        DateTime(2026, 10, 5, 8, 45),
        placeId: source.place.id,
      ),
    );
    expect(await sampling.needsSample(), isTrue);
  });
  test(
    'stale carry-over and unrelated geofence events do not suppress GPS',
    () async {
      evidence = [
        transition(
          LocationEventType.geofenceEnter,
          DateTime(2026, 10, 4, 20),
          placeId: source.place.id,
        ),
        transition(
          LocationEventType.geofenceEnter,
          source.start,
          placeId: 'other',
        ),
      ];
      expect(await sampling.needsSample(), isTrue);
    },
  );
  test('early window starts inclusively and avoids GPS before it', () async {
    now = DateTime(2026, 10, 5, 8, 45);
    expect(await sampling.needsSample(), isTrue);
    now = now.subtract(const Duration(microseconds: 1));
    expect(await sampling.needsSample(), isFalse);
  });
  test(
    'attendance-window end is inclusive and later instants avoid GPS',
    () async {
      now = source.end;
      expect(await sampling.needsSample(), isTrue);
      now = now.add(const Duration(microseconds: 1));
      expect(await sampling.needsSample(), isFalse);
    },
  );
  test('no current class avoids GPS and evidence queries', () async {
    now = DateTime(2026, 10, 5, 12);
    expect(await sampling.needsSample(), isFalse);
    verifyNever(
      () => events.query(
        from: any(named: 'from'),
        until: any(named: 'until'),
        placeId: any(named: 'placeId'),
      ),
    );
    when(() => courses.getSlots()).thenAnswer((_) async => []);
    expect(await sampling.needsSample(), isFalse);
  });
  test('overnight occurrences include the preceding local date', () async {
    final overnight = occurrence(start: DateTime(2026, 10, 4, 23, 30));
    when(() => courses.getSlots()).thenAnswer((_) async => [overnight.slot]);
    now = DateTime(2026, 10, 5, 0, 30);
    expect(await sampling.needsSample(), isTrue);
  });
  test('one unevidenced overlapping occurrence is enough to sample', () async {
    final other = campusPlace(id: 'other');
    when(places.getAll).thenAnswer((_) async => [source.place, other]);
    when(() => courses.getSlots()).thenAnswer(
      (_) async => [
        source.slot,
        source.slot.copyWith(id: 'slot2', placeId: other.id),
      ],
    );
    evidence = [
      transition(
        LocationEventType.geofenceEnter,
        source.start,
        placeId: source.place.id,
      ),
    ];
    expect(await sampling.needsSample(), isTrue);
  });
}
