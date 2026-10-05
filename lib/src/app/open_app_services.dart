import 'package:clock/clock.dart';
import 'package:did_i_assist/src/app/app_services.dart';
import 'package:did_i_assist/src/app/background_operations.dart';
import 'package:did_i_assist/src/data/database/app_database.dart';
import 'package:did_i_assist/src/domain/location/geofence_registrar.dart';
import 'package:did_i_assist/src/domain/location/location_permission_gateway.dart';
import 'package:did_i_assist/src/domain/location/position_provider.dart';
import 'package:did_i_assist/src/domain/repositories/class_sample_task_gateway.dart';
import 'package:did_i_assist/src/domain/repositories/notification_gateway.dart';
import 'package:did_i_assist/src/platform/background/background_geofence_callback.dart';
import 'package:did_i_assist/src/platform/background/workmanager_class_sample_gateway.dart';
import 'package:did_i_assist/src/platform/geolocator_permission_gateway.dart';
import 'package:did_i_assist/src/platform/geolocator_position_provider.dart';
import 'package:did_i_assist/src/platform/native_geofence_registrar.dart';
import 'package:did_i_assist/src/platform/notifications/create_notification_gateway.dart';
import 'package:did_i_assist/src/platform/notifications/lazy_notification_gateway.dart';

Future<AppServices> openAppServices({
  AppDatabase? database,
  GeofenceRegistrar? geofenceRegistrar,
  PositionProvider? positionProvider,
  LocationPermissionGateway? permissions,
  ClassSampleTaskGateway? sampleTasks,
  NotificationGateway? notifications,
  Clock? timeSource,
  Iterable<AttendanceResultListener> attendanceListeners = const [],
}) async {
  final sharedDatabase = database ?? AppDatabase();
  final source = timeSource ?? clock;
  try {
    return AppServices(
      database: sharedDatabase,
      geofenceRegistrar:
          geofenceRegistrar ??
          NativeGeofenceRegistrar(
            callback: backgroundGeofenceCallback,
          ),
      positionProvider: positionProvider ?? GeolocatorPositionProvider(),
      permissions: permissions ?? GeolocatorPermissionGateway(),
      sampleTasks:
          sampleTasks ??
          WorkmanagerClassSampleGateway(
            timeSource: source,
          ),
      notifications:
          notifications ??
          LazyNotificationGateway(
            () => createNotificationGateway(timeSource: source),
          ),
      timeSource: source,
      attendanceListeners: attendanceListeners,
    );
  } on Object {
    await sharedDatabase.close();
    rethrow;
  }
}
