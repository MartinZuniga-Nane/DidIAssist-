import 'package:did_i_attend/src/domain/location/geofence_transition.dart';
import 'package:did_i_attend/src/domain/location/position_fix.dart';
import 'package:did_i_attend/src/domain/models/models.dart';
import 'package:did_i_attend/src/domain/services/location_event_recorder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../location/mocks.dart';
import 'fixtures.dart';

void main() {
  final receivedAt = DateTime(2026, 10, 5, 9);
  final fix = PositionFix(
    position: eiffelTower(),
    accuracyMeters: 20,
    timestamp: receivedAt.subtract(const Duration(seconds: 10)),
  );
  late MockLocationEventRepository repository;
  late LocationEventRecorder recorder;
  late List<LocationEvent> appended;
  late int generated;

  setUpAll(
    () => registerFallbackValue(
      LocationEvent(
        id: 'fallback',
        type: LocationEventType.positionSample,
        position: eiffelTower(),
        recordedAt: receivedAt,
      ),
    ),
  );
  setUp(() {
    repository = MockLocationEventRepository();
    appended = [];
    generated = 0;
    when(() => repository.append(any())).thenAnswer((invocation) async {
      appended.add(invocation.positionalArguments.single as LocationEvent);
    });
    recorder = LocationEventRecorder(
      repository: repository,
      generateId: () => 'event-${++generated}',
    );
  });

  for (final type in [
    LocationEventType.geofenceEnter,
    LocationEventType.geofenceExit,
    LocationEventType.geofenceDwell,
  ]) {
    test('maps ${type.name} to one event per distinct place ID', () async {
      final events = await recorder.recordGeofenceTransition(
        placeIds: ['home', 'campus', 'home'],
        type: type,
        fix: fix,
        receivedAt: receivedAt,
      );
      expect(events, appended);
      expect(events.map((event) => event.placeId), ['home', 'campus']);
      expect(events.map((event) => event.id), ['event-1', 'event-2']);
      for (final event in events) {
        expect(event.type, type);
        expect(event.position, fix.position);
        expect(event.accuracyMeters, 20);
        expect(event.recordedAt, fix.timestamp);
        expect(event.recordedAt.isUtc, isTrue);
      }
      verify(() => repository.append(any())).called(2);
    });
  }

  test('missing fix uses UTC receipt time with no invented position', () async {
    final event = (await recorder.recordGeofenceTransition(
      placeIds: ['campus'],
      type: LocationEventType.geofenceEnter,
      receivedAt: receivedAt,
    )).single;
    expect(event.recordedAt, receivedAt.toUtc());
    expect(event.position, isNull);
    expect(event.accuracyMeters, isNull);
  });

  test(
    'a future fix uses receipt time while retaining position and accuracy',
    () async {
      final futureFix = fix.copyWith(
        timestamp: receivedAt.add(const Duration(microseconds: 1)),
      );
      final event = (await recorder.recordGeofenceTransition(
        placeIds: ['campus'],
        type: LocationEventType.geofenceEnter,
        fix: futureFix,
        receivedAt: receivedAt,
      )).single;
      expect(event.recordedAt, receivedAt.toUtc());
      expect(event.position, futureFix.position);
      expect(event.accuracyMeters, futureFix.accuracyMeters);
    },
  );

  test('a fix at exactly receipt time remains usable', () async {
    final event = (await recorder.recordGeofenceTransition(
      placeIds: ['campus'],
      type: LocationEventType.geofenceEnter,
      fix: fix.copyWith(timestamp: receivedAt),
      receivedAt: receivedAt,
    )).single;
    expect(event.recordedAt, receivedAt.toUtc());
    expect(event.position, fix.position);
  });

  test('position sample maps fix exactly and has no place ID', () async {
    final event = await recorder.recordPositionSample(fix);
    expect(event.id, 'event-1');
    expect(event.type, LocationEventType.positionSample);
    expect(event.placeId, isNull);
    expect(event.position, fix.position);
    expect(event.accuracyMeters, fix.accuracyMeters);
    expect(event.recordedAt, fix.timestamp);
    expect(appended, [event]);
  });

  test('sample with unknown accuracy preserves null', () async {
    expect(
      (await recorder.recordPositionSample(
        fix.copyWith(accuracyMeters: () => null),
      )).accuracyMeters,
      isNull,
    );
  });

  test('default generator creates distinct version-four UUIDs', () async {
    final defaults = LocationEventRecorder(repository: repository);
    final first = await defaults.recordPositionSample(fix);
    final second = await defaults.recordPositionSample(fix);
    final pattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    expect(pattern.hasMatch(first.id), isTrue);
    expect(pattern.hasMatch(second.id), isTrue);
    expect(first.id, isNot(second.id));
  });

  test('empty batches do not generate IDs or append events', () async {
    expect(
      await recorder.recordGeofenceTransition(
        placeIds: [],
        type: LocationEventType.geofenceEnter,
        receivedAt: receivedAt,
      ),
      isEmpty,
    );
    expect(generated, 0);
    verifyNever(() => repository.append(any()));
  });

  test('invalid type and place IDs fail before any write', () async {
    await expectLater(
      recorder.recordGeofenceTransition(
        placeIds: ['home'],
        type: LocationEventType.positionSample,
        receivedAt: receivedAt,
      ),
      throwsArgumentError,
    );
    await expectLater(
      recorder.recordGeofenceTransition(
        placeIds: ['home', ' '],
        type: LocationEventType.geofenceEnter,
        receivedAt: receivedAt,
      ),
      throwsArgumentError,
    );
    expect(generated, 0);
    verifyNever(() => repository.append(any()));
  });

  test('repository failures propagate to the caller', () async {
    when(
      () => repository.append(any()),
    ).thenThrow(Exception('storage unavailable'));
    await expectLater(recorder.recordPositionSample(fix), throwsException);
  });

  test(
    'implements the injectable background handler by recording its batch',
    () async {
      await recorder.handle(
        GeofenceTransition(
          placeIds: const ['home', 'campus'],
          type: LocationEventType.geofenceExit,
          fix: fix,
          receivedAt: receivedAt,
        ),
      );
      expect(appended, hasLength(2));
      expect(
        appended.every((event) => event.type == LocationEventType.geofenceExit),
        isTrue,
      );
    },
  );
}
