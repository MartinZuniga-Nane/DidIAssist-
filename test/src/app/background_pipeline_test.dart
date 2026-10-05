import 'dart:async';

import 'package:did_i_assist/src/app/background_operations.dart';
import 'package:did_i_assist/src/app/background_pipeline.dart';
import 'package:did_i_assist/src/core/local_date.dart';
import 'package:did_i_assist/src/domain/location/geofence_transition.dart';
import 'package:did_i_assist/src/domain/location/position_provider.dart';
import 'package:did_i_assist/src/domain/models/models.dart';
import 'package:did_i_assist/src/domain/services/position_sampler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../domain/models/fixtures.dart';

final class _MockOperations extends Mock implements BackgroundOperations {}

final class _MockListener extends Mock implements AttendanceResultListener {}

void main() {
  late _MockOperations operations;
  late _MockListener listener;
  late BackgroundPipeline pipeline;
  final transition = GeofenceTransition(
    placeIds: const [placeId],
    type: LocationEventType.geofenceEnter,
    receivedAt: DateTime.utc(2026, 10, 5, 9),
  );

  setUpAll(() {
    registerFallbackValue(transition);
    registerFallbackValue(<AttendanceRecord>[]);
  });
  setUp(() {
    operations = _MockOperations();
    listener = _MockListener();
    pipeline = BackgroundPipeline(
      operations: operations,
      listeners: [listener],
    );
    when(
      () => operations.recordTransition(any()),
    ).thenAnswer((_) async => [sampleEvent()]);
    when(operations.syncGeofences).thenAnswer((_) async {});
    when(operations.needsPositionSample).thenAnswer((_) async => true);
    when(operations.samplePosition).thenAnswer(
      (_) async => PositionSampleRecorded(
        sampleEvent().copyWith(type: LocationEventType.positionSample),
      ),
    );
    when(
      operations.evaluateAttendance,
    ).thenAnswer((_) async => [sampleAttendance()]);
    when(operations.recordTrips).thenAnswer((_) async => [sampleTrip()]);
    when(operations.scheduleClassSamples).thenAnswer((_) async {});
    when(() => listener.onAttendanceWritten(any())).thenAnswer((_) async {});
  });

  test(
    'geofence records first, evaluates, records trips, then notifies',
    () async {
      final result = await pipeline.onGeofenceTransition(transition);
      verifyInOrder([
        () => operations.recordTransition(transition),
        operations.evaluateAttendance,
        operations.recordTrips,
        () => listener.onAttendanceWritten([sampleAttendance()]),
      ]);
      expect(result.events, [sampleEvent()]);
      expect(result.attendance, [sampleAttendance()]);
      expect(result.trips, [sampleTrip()]);
      expect(result.succeeded, isTrue);
      expect(result.events.clear, throwsUnsupportedError);
      expect(result.attendance.clear, throwsUnsupportedError);
      expect(result.failures.clear, throwsUnsupportedError);
    },
  );

  test('later stages wait until persistence completes', () async {
    final recorded = Completer<List<LocationEvent>>();
    when(
      () => operations.recordTransition(any()),
    ).thenAnswer((_) => recorded.future);
    final pending = pipeline.onGeofenceTransition(transition);
    await Future<void>.delayed(Duration.zero);
    verifyNever(operations.evaluateAttendance);
    recorded.complete([sampleEvent()]);
    expect((await pending).succeeded, isTrue);
    verify(operations.evaluateAttendance).called(1);
  });

  test(
    'attendance failure preserves evidence and still records trips',
    () async {
      final error = StateError('attendance failed');
      when(operations.evaluateAttendance).thenThrow(error);
      final result = await pipeline.onGeofenceTransition(transition);
      expect(result.events, [sampleEvent()]);
      expect(result.trips, [sampleTrip()]);
      expect(result.failures.single.stage, BackgroundStage.evaluateAttendance);
      expect(result.failures.single.error, same(error));
      verifyNever(() => listener.onAttendanceWritten(any()));
    },
  );

  test('trip failure does not suppress attendance listeners', () async {
    when(operations.recordTrips).thenThrow(Exception('trip failed'));
    final result = await pipeline.onGeofenceTransition(transition);
    expect(result.events, [sampleEvent()]);
    expect(result.attendance, [sampleAttendance()]);
    expect(result.failures.single.stage, BackgroundStage.recordTrips);
    verify(() => listener.onAttendanceWritten([sampleAttendance()])).called(1);
  });

  test(
    'each listener is isolated and receives an immutable written list',
    () async {
      final second = _MockListener();
      when(() => listener.onAttendanceWritten(any())).thenAnswer((
        invocation,
      ) async {
        final records =
            invocation.positionalArguments.single as List<AttendanceRecord>;
        expect(records.clear, throwsUnsupportedError);
        throw Exception('listener failed');
      });
      when(() => second.onAttendanceWritten(any())).thenAnswer((_) async {});
      pipeline
        ..addListener(second)
        ..addListener(second);
      final result = await pipeline.onGeofenceTransition(transition);
      expect(result.failures.single.stage, BackgroundStage.notifyListener);
      verify(() => second.onAttendanceWritten([sampleAttendance()])).called(1);
      pipeline.removeListener(second);
      await pipeline.onGeofenceTransition(transition);
      verifyNever(() => second.onAttendanceWritten(any()));
    },
  );

  test(
    'native handler propagates persistence failures after isolated stages',
    () async {
      when(
        () => operations.recordTransition(any()),
      ).thenThrow(Exception('storage failed'));
      final result = await pipeline.onGeofenceTransition(transition);
      expect(result.failures.single.stage, BackgroundStage.recordTransition);
      expect(result.attendance, [sampleAttendance()]);
      await expectLater(pipeline.handle(transition), throwsException);
    },
  );

  test(
    'periodic stage ordering includes conditional sampling and scheduling',
    () async {
      final result = await pipeline.onPeriodicTick();
      verifyInOrder([
        operations.syncGeofences,
        operations.needsPositionSample,
        operations.samplePosition,
        operations.evaluateAttendance,
        operations.recordTrips,
        () => listener.onAttendanceWritten(any()),
        operations.scheduleClassSamples,
      ]);
      expect(result.sampleResult, isA<PositionSampleRecorded>());
      expect(result.events, hasLength(1));
      expect(result.succeeded, isTrue);
    },
  );

  test('periodic tick avoids GPS when no sample is needed', () async {
    when(operations.needsPositionSample).thenAnswer((_) async => false);
    expect((await pipeline.onPeriodicTick()).succeeded, isTrue);
    verifyNever(operations.samplePosition);
    verify(operations.evaluateAttendance).called(1);
    verify(operations.scheduleClassSamples).called(1);
  });

  test(
    'periodic failures remain isolated through the final scheduling stage',
    () async {
      when(operations.syncGeofences).thenThrow(Exception('geofences failed'));
      when(
        operations.samplePosition,
      ).thenThrow(Exception('sample persistence failed'));
      when(operations.recordTrips).thenThrow(Exception('trip failed'));
      when(
        () => listener.onAttendanceWritten(any()),
      ).thenThrow(Exception('listener failed'));
      when(
        operations.scheduleClassSamples,
      ).thenThrow(Exception('schedule failed'));
      final result = await pipeline.onPeriodicTick();
      expect(result.attendance, [sampleAttendance()]);
      expect(result.failures.map((failure) => failure.stage), [
        BackgroundStage.syncGeofences,
        BackgroundStage.samplePosition,
        BackgroundStage.recordTrips,
        BackgroundStage.notifyListener,
        BackgroundStage.scheduleClassSamples,
      ]);
    },
  );

  test('sampling-policy failure skips GPS and continues evaluation', () async {
    when(operations.needsPositionSample).thenThrow(Exception('query failed'));
    final result = await pipeline.onPeriodicTick();
    expect(result.failures.single.stage, BackgroundStage.checkSampling);
    verifyNever(operations.samplePosition);
    verify(operations.evaluateAttendance).called(1);
    verify(operations.scheduleClassSamples).called(1);
  });

  test(
    'expected GPS unavailability is reported without requesting retry',
    () async {
      when(operations.samplePosition).thenAnswer(
        (_) async =>
            const PositionSampleFailed(PositionFailureReason.permissionDenied),
      );
      final result = await pipeline.onPeriodicTick();
      expect(
        result.sampleResult,
        const PositionSampleFailed(PositionFailureReason.permissionDenied),
      );
      expect(result.succeeded, isTrue);
      verify(operations.evaluateAttendance).called(1);
    },
  );

  test(
    'class task takes one sample, evaluates and invokes listeners',
    () async {
      final result = await pipeline.onClassSampleTask(
        slotId,
        LocalDate(2026, 10, 5),
      );
      verifyInOrder([
        operations.samplePosition,
        operations.evaluateAttendance,
        () => listener.onAttendanceWritten([sampleAttendance()]),
      ]);
      verifyNever(operations.recordTrips);
      verifyNever(operations.syncGeofences);
      verifyNever(operations.scheduleClassSamples);
      expect(result.succeeded, isTrue);
    },
  );

  test('class sample failure still evaluates historical evidence', () async {
    when(operations.samplePosition).thenThrow(Exception('storage failed'));
    final result = await pipeline.onClassSampleTask(
      slotId,
      LocalDate(2026, 10, 5),
    );
    expect(result.failures.single.stage, BackgroundStage.samplePosition);
    expect(result.attendance, [sampleAttendance()]);
    verify(() => listener.onAttendanceWritten(any())).called(1);
  });

  test(
    'empty written results are supplied to listeners and invalid IDs fail',
    () async {
      when(operations.evaluateAttendance).thenAnswer((_) async => []);
      await pipeline.onGeofenceTransition(transition);
      verify(() => listener.onAttendanceWritten([])).called(1);
      await expectLater(
        pipeline.onClassSampleTask('', LocalDate(2026, 10, 5)),
        throwsArgumentError,
      );
    },
  );
}
