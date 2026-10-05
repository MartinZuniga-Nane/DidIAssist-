import 'dart:ui';

import 'package:clock/clock.dart';
import 'package:did_i_assist/src/app/app_services.dart';
import 'package:did_i_assist/src/app/background_operations.dart';
import 'package:did_i_assist/src/data/database/app_database.dart';
import 'package:did_i_assist/src/platform/background/background_geofence_callback.dart';
import 'package:did_i_assist/src/platform/background/workmanager_class_sample_gateway.dart';
import 'package:did_i_assist/src/platform/geolocator_permission_gateway.dart';
import 'package:did_i_assist/src/platform/geolocator_position_provider.dart';
import 'package:did_i_assist/src/platform/native_geofence_registrar.dart';
import 'package:flutter/widgets.dart';

Future<AppServices> openBackgroundServices({
  Iterable<AttendanceResultListener> attendanceListeners = const [],
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Headless engines register plugins through their native registrant callback;
  // Dart-spawned background isolates need the Dart registrant as well.
  if (RootIsolateToken.instance == null) {
    DartPluginRegistrant.ensureInitialized();
  }
  final database = AppDatabase();
  try {
    return AppServices(
      database: database,
      geofenceRegistrar: NativeGeofenceRegistrar(
        callback: backgroundGeofenceCallback,
      ),
      positionProvider: GeolocatorPositionProvider(),
      permissions: GeolocatorPermissionGateway(),
      sampleTasks: WorkmanagerClassSampleGateway(),
      timeSource: clock,
      // UI listeners do not cross isolates. Construct background listeners here
      // or supply them from the background entry point's own bootstrap.
      attendanceListeners: attendanceListeners,
    );
  } catch (_) {
    await database.close();
    rethrow;
  }
}
