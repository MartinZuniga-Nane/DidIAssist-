import 'package:did_i_assist/src/domain/models/attendance_policy.dart';
import 'package:did_i_assist/src/domain/models/model_validation.dart';
import 'package:did_i_assist/src/domain/models/travel_mode.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

@immutable
final class UserSettings extends Equatable {
  UserSettings({
    this.defaultTravelMode = TravelMode.walking,
    this.departureBufferMinutes = 5,
    AttendancePolicy? attendancePolicy,
    this.notificationsEnabled = true,
  }) : attendancePolicy = attendancePolicy ?? AttendancePolicy() {
    requireNonNegative(departureBufferMinutes, 'departureBufferMinutes');
  }

  final TravelMode defaultTravelMode;
  final int departureBufferMinutes;
  final AttendancePolicy attendancePolicy;
  final bool notificationsEnabled;

  UserSettings copyWith({
    TravelMode? defaultTravelMode,
    int? departureBufferMinutes,
    AttendancePolicy? attendancePolicy,
    bool? notificationsEnabled,
  }) => UserSettings(
    defaultTravelMode: defaultTravelMode ?? this.defaultTravelMode,
    departureBufferMinutes:
        departureBufferMinutes ?? this.departureBufferMinutes,
    attendancePolicy: attendancePolicy ?? this.attendancePolicy,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
  );

  @override
  List<Object> get props => [
    defaultTravelMode,
    departureBufferMinutes,
    attendancePolicy,
    notificationsEnabled,
  ];
}
