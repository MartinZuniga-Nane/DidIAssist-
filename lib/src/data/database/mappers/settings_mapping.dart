import 'package:did_i_assist/src/data/database/app_database.dart';
import 'package:did_i_assist/src/domain/models/attendance_policy.dart';
import 'package:did_i_assist/src/domain/models/travel_mode.dart';
import 'package:did_i_assist/src/domain/models/user_settings.dart';
import 'package:drift/drift.dart';

UserSettings settingsFromRow(UserSettingsRow row) => UserSettings(
  defaultTravelMode: TravelMode.values.byName(row.defaultTravelMode),
  departureBufferMinutes: row.departureBufferMinutes,
  attendancePolicy: AttendancePolicy(
    earlyWindowMinutes: row.earlyWindowMinutes,
    graceMinutes: row.graceMinutes,
    lateUntilMinutes: row.lateUntilMinutes,
    maxAccuracyMeters: row.maxAccuracyMeters,
  ),
  notificationsEnabled: row.notificationsEnabled,
);

UserSettingsTableCompanion settingsToCompanion(UserSettings settings) =>
    UserSettingsTableCompanion.insert(
      id: const Value(1),
      defaultTravelMode: settings.defaultTravelMode.name,
      departureBufferMinutes: settings.departureBufferMinutes,
      earlyWindowMinutes: settings.attendancePolicy.earlyWindowMinutes,
      graceMinutes: settings.attendancePolicy.graceMinutes,
      lateUntilMinutes: Value(settings.attendancePolicy.lateUntilMinutes),
      maxAccuracyMeters: settings.attendancePolicy.maxAccuracyMeters,
      notificationsEnabled: settings.notificationsEnabled,
    );
