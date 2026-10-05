import 'package:did_i_assist/src/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  test(
    'defaults to walking, five minutes buffer and notifications enabled',
    () {
      final settings = UserSettings();
      expect(settings.defaultTravelMode, TravelMode.walking);
      expect(settings.departureBufferMinutes, 5);
      expect(settings.attendancePolicy, AttendancePolicy());
      expect(settings.notificationsEnabled, isTrue);
    },
  );

  test('has value equality and copyWith changes each field', () {
    final settings = UserSettings();
    expectValueEquality(settings, UserSettings(), [
      settings.copyWith(defaultTravelMode: TravelMode.cycling),
      settings.copyWith(departureBufferMinutes: 10),
      settings.copyWith(attendancePolicy: AttendancePolicy(graceMinutes: 5)),
      settings.copyWith(notificationsEnabled: false),
    ]);
    expect(settings.copyWith(), settings);
    expect(
      settings.copyWith(notificationsEnabled: false).attendancePolicy,
      settings.attendancePolicy,
    );
  });

  test('accepts zero departure buffer and rejects negative values', () {
    expect(UserSettings(departureBufferMinutes: 0).departureBufferMinutes, 0);
    expect(
      () => UserSettings(departureBufferMinutes: -1),
      throwsArgumentError,
    );
    expect(
      () => UserSettings().copyWith(departureBufferMinutes: -1),
      throwsArgumentError,
    );
  });
}
