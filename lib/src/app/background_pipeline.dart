import 'package:did_i_assist/src/app/background_operations.dart';
import 'package:did_i_assist/src/core/local_date.dart';
import 'package:did_i_assist/src/domain/location/geofence_transition.dart';
import 'package:did_i_assist/src/domain/models/attendance_record.dart';
import 'package:did_i_assist/src/domain/models/location_event.dart';
import 'package:did_i_assist/src/domain/models/model_validation.dart';
import 'package:did_i_assist/src/domain/models/trip.dart';
import 'package:did_i_assist/src/domain/services/position_sampler.dart';

final class BackgroundPipeline implements BackgroundTaskTarget {
  BackgroundPipeline({
    required BackgroundOperations operations,
    Iterable<AttendanceResultListener> listeners = const [],
  }) : _operations = operations,
       _listeners = [...listeners];

  final BackgroundOperations _operations;
  final List<AttendanceResultListener> _listeners;

  void addListener(AttendanceResultListener listener) {
    if (!_listeners.contains(listener)) _listeners.add(listener);
  }

  void removeListener(AttendanceResultListener listener) =>
      _listeners.remove(listener);

  Future<BackgroundResult> onGeofenceTransition(
    GeofenceTransition transition,
  ) async {
    final run = _PipelineRun();
    await run.attempt(BackgroundStage.recordTransition, () async {
      run.events.addAll(await _operations.recordTransition(transition));
    });
    await _evaluate(run, includeTrips: true);
    return run.result;
  }

  @override
  Future<void> handle(GeofenceTransition transition) async {
    final result = await onGeofenceTransition(transition);
    // Native callbacks must not acknowledge a failed evidence write.
    for (final failure in result.failures) {
      if (failure.stage == BackgroundStage.recordTransition) {
        Error.throwWithStackTrace(failure.error, failure.stackTrace);
      }
    }
  }

  @override
  Future<BackgroundResult> onPeriodicTick() async {
    final run = _PipelineRun();
    await run.attempt(BackgroundStage.syncGeofences, _operations.syncGeofences);
    var needsSample = false;
    await run.attempt(BackgroundStage.checkSampling, () async {
      needsSample = await _operations.needsPositionSample();
    });
    if (needsSample) await _sample(run);
    await _evaluate(run, includeTrips: true);
    await run.attempt(
      BackgroundStage.scheduleClassSamples,
      _operations.scheduleClassSamples,
    );
    return run.result;
  }

  @override
  Future<BackgroundResult> onClassSampleTask(
    String slotId,
    LocalDate date,
  ) async {
    requireNonBlank(slotId, 'slotId');
    final run = _PipelineRun();
    await _sample(run);
    await _evaluate(run, includeTrips: false);
    return run.result;
  }

  Future<void> _sample(_PipelineRun run) =>
      run.attempt(BackgroundStage.samplePosition, () async {
        final result = await _operations.samplePosition();
        run.sampleResult = result;
        if (result case PositionSampleRecorded(:final event)) {
          run.events.add(event);
        }
      });

  Future<void> _evaluate(_PipelineRun run, {required bool includeTrips}) async {
    var evaluated = false;
    await run.attempt(BackgroundStage.evaluateAttendance, () async {
      run.attendance.addAll(await _operations.evaluateAttendance());
      evaluated = true;
    });
    if (includeTrips) {
      await run.attempt(BackgroundStage.recordTrips, () async {
        run.trips.addAll(await _operations.recordTrips());
      });
    }
    if (evaluated) {
      final records = List<AttendanceRecord>.unmodifiable(run.attendance);
      for (final listener in List<AttendanceResultListener>.of(_listeners)) {
        await run.attempt(
          BackgroundStage.notifyListener,
          () => listener.onAttendanceWritten(records),
        );
      }
    }
  }
}

final class _PipelineRun {
  final events = <LocationEvent>[];
  final attendance = <AttendanceRecord>[];
  final trips = <Trip>[];
  final failures = <BackgroundStageFailure>[];
  PositionSampleResult? sampleResult;

  Future<void> attempt(
    BackgroundStage stage,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } on Object catch (error, stackTrace) {
      failures.add(BackgroundStageFailure(stage, error, stackTrace));
    }
  }

  BackgroundResult get result => BackgroundResult(
    events: events,
    attendance: attendance,
    trips: trips,
    failures: failures,
    sampleResult: sampleResult,
  );
}
