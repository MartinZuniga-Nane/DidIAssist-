import 'package:clock/clock.dart';
import 'package:did_i_assist/src/app/attendance_sampling_policy.dart';
import 'package:did_i_assist/src/app/background_operations.dart';
import 'package:did_i_assist/src/app/background_pipeline.dart';
import 'package:did_i_assist/src/app/class_sample_scheduler.dart';
import 'package:did_i_assist/src/app/notification_attendance_listener.dart';
import 'package:did_i_assist/src/app/permission_onboarding.dart';
import 'package:did_i_assist/src/data/database/app_database.dart';
import 'package:did_i_assist/src/data/repositories/drift_attendance_repository.dart';
import 'package:did_i_assist/src/data/repositories/drift_class_sample_schedule_store.dart';
import 'package:did_i_assist/src/data/repositories/drift_course_repository.dart';
import 'package:did_i_assist/src/data/repositories/drift_location_event_repository.dart';
import 'package:did_i_assist/src/data/repositories/drift_place_repository.dart';
import 'package:did_i_assist/src/data/repositories/drift_settings_repository.dart';
import 'package:did_i_assist/src/data/repositories/drift_trip_repository.dart';
import 'package:did_i_assist/src/domain/location/geofence_registrar.dart';
import 'package:did_i_assist/src/domain/location/geofence_transition.dart';
import 'package:did_i_assist/src/domain/location/location_permission_gateway.dart';
import 'package:did_i_assist/src/domain/location/position_provider.dart';
import 'package:did_i_assist/src/domain/models/attendance_record.dart';
import 'package:did_i_assist/src/domain/models/location_event.dart';
import 'package:did_i_assist/src/domain/models/trip.dart';
import 'package:did_i_assist/src/domain/repositories/class_sample_task_gateway.dart';
import 'package:did_i_assist/src/domain/repositories/notification_gateway.dart';
import 'package:did_i_assist/src/domain/services/attendance_evaluator.dart';
import 'package:did_i_assist/src/domain/services/attendance_notifier.dart';
import 'package:did_i_assist/src/domain/services/attendance_service.dart';
import 'package:did_i_assist/src/domain/services/departure_service.dart';
import 'package:did_i_assist/src/domain/services/geofence_sync.dart';
import 'package:did_i_assist/src/domain/services/location_event_recorder.dart';
import 'package:did_i_assist/src/domain/services/position_sampler.dart';
import 'package:did_i_assist/src/domain/services/reminder_service.dart';
import 'package:did_i_assist/src/domain/services/schedule_resolver.dart';
import 'package:did_i_assist/src/domain/services/trip_recorder.dart';

abstract interface class BackgroundTaskServices {
  BackgroundTaskTarget get pipeline;
  Clock get timeSource;
  Future<void> dispose();
}

final class AppServices implements BackgroundTaskServices {
  factory AppServices({
    required AppDatabase database,
    required GeofenceRegistrar geofenceRegistrar,
    required PositionProvider positionProvider,
    required LocationPermissionGateway permissions,
    required ClassSampleTaskGateway sampleTasks,
    required NotificationGateway notifications,
    required Clock timeSource,
    Iterable<AttendanceResultListener> attendanceListeners = const [],
    String Function()? generateId,
  }) {
    final places = DriftPlaceRepository(database);
    final courses = DriftCourseRepository(database);
    final attendance = DriftAttendanceRepository(database);
    final events = DriftLocationEventRepository(database);
    final trips = DriftTripRepository(database);
    final settings = DriftSettingsRepository(database);
    const resolver = ScheduleResolver();
    final evaluator = AttendanceEvaluator();
    final attendanceService = AttendanceService(
      courseRepository: courses,
      placeRepository: places,
      attendanceRepository: attendance,
      locationEventRepository: events,
      settingsRepository: settings,
      timeSource: timeSource,
      idGenerator: generateId,
      evaluator: evaluator,
    );
    final tripRecorder = TripRecorder(
      locationEventRepository: events,
      placeRepository: places,
      tripRepository: trips,
      timeSource: timeSource,
    );
    final geofenceSync = GeofenceSync(
      placeRepository: places,
      registrar: geofenceRegistrar,
    );
    final recorder = LocationEventRecorder(
      repository: events,
      generateId: generateId,
    );
    final sampler = PositionSampler(
      positionProvider: positionProvider,
      recorder: recorder,
    );
    final samplingPolicy = AttendanceSamplingPolicy(
      courses: courses,
      places: places,
      events: events,
      settings: settings,
      timeSource: timeSource,
      evaluator: evaluator,
    );
    final scheduler = ClassSampleScheduler(
      courses: courses,
      places: places,
      settings: settings,
      store: DriftClassSampleScheduleStore(database),
      gateway: sampleTasks,
      timeSource: timeSource,
    );
    final departureService = DepartureService(
      placeRepository: places,
      settingsRepository: settings,
      tripRepository: trips,
      timeSource: timeSource,
    );
    final reminderService = ReminderService(
      courseRepository: courses,
      placeRepository: places,
      settingsRepository: settings,
      departureService: departureService,
      gateway: notifications,
      timeSource: timeSource,
    );
    final attendanceNotifier = AttendanceNotifier(
      gateway: notifications,
      settingsRepository: settings,
      courseRepository: courses,
    );
    final permissionOnboarding = PermissionOnboarding(
      location: permissions,
      notifications: notifications,
      syncGeofences: geofenceSync.sync,
      syncClassSamples: () async {
        await scheduler.sync();
      },
    );
    return AppServices._(
      database: database,
      timeSource: timeSource,
      permissions: permissions,
      notifications: notifications,
      reminderService: reminderService,
      attendanceNotifier: attendanceNotifier,
      permissionOnboarding: permissionOnboarding,
      places: places,
      courses: courses,
      attendance: attendance,
      events: events,
      trips: trips,
      settings: settings,
      resolver: resolver,
      attendanceService: attendanceService,
      tripRecorder: tripRecorder,
      geofenceSync: geofenceSync,
      locationRecorder: recorder,
      positionSampler: sampler,
      samplingPolicy: samplingPolicy,
      classSampleScheduler: scheduler,
      departureService: departureService,
      pipeline: BackgroundPipeline(
        operations: _ServiceOperations(
          recorder: recorder,
          geofences: geofenceSync,
          samplingPolicy: samplingPolicy,
          sampler: sampler,
          attendance: attendanceService,
          trips: tripRecorder,
          scheduler: scheduler,
          reminders: reminderService,
          permissions: permissions,
        ),
        listeners: [
          NotificationAttendanceListener(attendanceNotifier),
          ...attendanceListeners,
        ],
      ),
    );
  }

  AppServices._({
    required AppDatabase database,
    required this.timeSource,
    required this.permissions,
    required this.notifications,
    required this.reminderService,
    required this.attendanceNotifier,
    required this.permissionOnboarding,
    required this.places,
    required this.courses,
    required this.attendance,
    required this.events,
    required this.trips,
    required this.settings,
    required this.resolver,
    required this.attendanceService,
    required this.tripRecorder,
    required this.geofenceSync,
    required this.locationRecorder,
    required this.positionSampler,
    required this.samplingPolicy,
    required this.classSampleScheduler,
    required this.departureService,
    required this.pipeline,
  }) : _database = database;

  final AppDatabase _database;
  @override
  final Clock timeSource;
  final LocationPermissionGateway permissions;
  final NotificationGateway notifications;
  final ReminderService reminderService;
  final AttendanceNotifier attendanceNotifier;
  final PermissionOnboarding permissionOnboarding;
  final DriftPlaceRepository places;
  final DriftCourseRepository courses;
  final DriftAttendanceRepository attendance;
  final DriftLocationEventRepository events;
  final DriftTripRepository trips;
  final DriftSettingsRepository settings;
  final ScheduleResolver resolver;
  final AttendanceService attendanceService;
  final TripRecorder tripRecorder;
  final GeofenceSync geofenceSync;
  final LocationEventRecorder locationRecorder;
  final PositionSampler positionSampler;
  final AttendanceSamplingPolicy samplingPolicy;
  final ClassSampleScheduler classSampleScheduler;
  final DepartureService departureService;
  @override
  final BackgroundPipeline pipeline;
  Future<void>? _closing;

  Future<void> syncGeofencesWhenPermitted() async {
    if (await permissions.check() == LocationPermissionStatus.always) {
      await geofenceSync.sync();
    }
  }

  Future<void> syncClassSamplesWhenPermitted() async {
    if (await permissions.check() == LocationPermissionStatus.always) {
      await classSampleScheduler.sync();
    }
  }

  @override
  Future<void> dispose() => _closing ??= _database.close();
}

final class _ServiceOperations implements BackgroundOperations {
  const _ServiceOperations({
    required this.recorder,
    required this.geofences,
    required this.samplingPolicy,
    required this.sampler,
    required this.attendance,
    required this.trips,
    required this.scheduler,
    required this.reminders,
    required this.permissions,
  });

  final LocationEventRecorder recorder;
  final GeofenceSync geofences;
  final AttendanceSamplingPolicy samplingPolicy;
  final PositionSampler sampler;
  final AttendanceService attendance;
  final TripRecorder trips;
  final ClassSampleScheduler scheduler;
  final ReminderService reminders;
  final LocationPermissionGateway permissions;

  @override
  Future<List<LocationEvent>> recordTransition(GeofenceTransition transition) =>
      recorder.recordGeofenceTransition(
        placeIds: transition.placeIds,
        type: transition.type,
        receivedAt: transition.receivedAt,
        fix: transition.fix,
      );
  @override
  Future<void> syncGeofences() async {
    if (await permissions.check() == LocationPermissionStatus.always) {
      await geofences.sync();
    }
  }

  @override
  Future<bool> needsPositionSample() => samplingPolicy.needsSample();
  @override
  Future<PositionSampleResult> samplePosition() async {
    final status = await permissions.check();
    if (status != LocationPermissionStatus.always) {
      return PositionSampleFailed(
        status == LocationPermissionStatus.serviceDisabled
            ? PositionFailureReason.serviceDisabled
            : PositionFailureReason.permissionDenied,
      );
    }
    return sampler.sample();
  }

  @override
  Future<List<AttendanceRecord>> evaluateAttendance() =>
      attendance.evaluateRecent();
  @override
  Future<List<Trip>> recordTrips() => trips.recordRecent();
  @override
  Future<void> scheduleClassSamples() async {
    if (await permissions.check() == LocationPermissionStatus.always) {
      await scheduler.sync();
    }
  }

  @override
  Future<void> reconcileReminders() async {
    await reminders.reconcile();
  }
}
