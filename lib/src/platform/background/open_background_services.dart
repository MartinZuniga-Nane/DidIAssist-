import 'dart:ui';

import 'package:did_i_attend/src/app/app_services.dart';
import 'package:did_i_attend/src/app/background_operations.dart';
import 'package:did_i_attend/src/app/open_app_services.dart';
import 'package:flutter/widgets.dart';

Future<AppServices> openBackgroundServices({
  Iterable<AttendanceResultListener> attendanceListeners = const [],
  Future<AppServices> Function({
        required Iterable<AttendanceResultListener> attendanceListeners,
      })
      openServices =
      openAppServices,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Headless engines use their native registrant; Dart-spawned isolates also
  // require the Dart registrant before any platform port is invoked.
  if (RootIsolateToken.instance == null) {
    DartPluginRegistrant.ensureInitialized();
  }
  return openServices(attendanceListeners: attendanceListeners);
}
