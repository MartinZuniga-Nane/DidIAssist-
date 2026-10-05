import 'package:did_i_assist/src/core/local_date.dart';
import 'package:did_i_assist/src/domain/location/background_location_handler.dart';
import 'package:did_i_assist/src/domain/location/geofence_transition.dart';
import 'package:did_i_assist/src/domain/models/attendance_record.dart';
import 'package:did_i_assist/src/domain/models/location_event.dart';
import 'package:did_i_assist/src/domain/models/trip.dart';
import 'package:did_i_assist/src/domain/services/position_sampler.dart';

abstract interface class BackgroundOperations {
  Future<List<LocationEvent>> recordTransition(GeofenceTransition transition);
  Future<void> syncGeofences();
  Future<bool> needsPositionSample();
  Future<PositionSampleResult> samplePosition();
  Future<List<AttendanceRecord>> evaluateAttendance();
  Future<List<Trip>> recordTrips();
  Future<void> scheduleClassSamples();
}

// A named hook allows each isolate to construct its own result listeners.
// ignore: one_member_abstracts
abstract interface class AttendanceResultListener {
  Future<void> onAttendanceWritten(List<AttendanceRecord> records);
}

enum BackgroundStage {
  recordTransition,
  syncGeofences,
  checkSampling,
  samplePosition,
  evaluateAttendance,
  recordTrips,
  notifyListener,
  scheduleClassSamples,
}

final class BackgroundStageFailure {
  const BackgroundStageFailure(this.stage, this.error, this.stackTrace);

  final BackgroundStage stage;
  final Object error;
  final StackTrace stackTrace;
}

final class BackgroundResult {
  BackgroundResult({
    Iterable<LocationEvent> events = const [],
    Iterable<AttendanceRecord> attendance = const [],
    Iterable<Trip> trips = const [],
    Iterable<BackgroundStageFailure> failures = const [],
    this.sampleResult,
  }) : events = List.unmodifiable(events),
       attendance = List.unmodifiable(attendance),
       trips = List.unmodifiable(trips),
       failures = List.unmodifiable(failures);

  final List<LocationEvent> events;
  final List<AttendanceRecord> attendance;
  final List<Trip> trips;
  final List<BackgroundStageFailure> failures;
  final PositionSampleResult? sampleResult;

  bool get succeeded => failures.isEmpty;
}

abstract interface class BackgroundTaskTarget
    implements BackgroundLocationHandler {
  Future<BackgroundResult> onPeriodicTick();
  Future<BackgroundResult> onClassSampleTask(String slotId, LocalDate date);
}
