import 'package:did_i_attend/src/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  test(
    'defaults match attendance windows and accuracy in the specification',
    () {
      final policy = AttendancePolicy();
      expect(policy.earlyWindowMinutes, 15);
      expect(policy.graceMinutes, 10);
      expect(policy.lateUntilMinutes, isNull);
      expect(policy.maxAccuracyMeters, 200);
    },
  );

  test(
    'has value equality and can copy, replace and clear nullable cutoffs',
    () {
      final policy = AttendancePolicy();
      expectValueEquality(policy, AttendancePolicy(), [
        policy.copyWith(earlyWindowMinutes: 20),
        policy.copyWith(graceMinutes: 5),
        policy.copyWith(lateUntilMinutes: () => 30),
        policy.copyWith(maxAccuracyMeters: 100),
      ]);
      expect(policy.copyWith(), policy);
      final limited = policy.copyWith(lateUntilMinutes: () => 30);
      expect(limited.copyWith().lateUntilMinutes, 30);
      expect(limited.copyWith(lateUntilMinutes: () => null), policy);
    },
  );

  test('accepts zero windows and cutoff equal to grace', () {
    final policy = AttendancePolicy(
      earlyWindowMinutes: 0,
      graceMinutes: 0,
      lateUntilMinutes: 0,
    );
    expect(policy.lateUntilMinutes, 0);
  });

  test(
    'rejects negative windows, inverted cutoff and invalid accuracy limits',
    () {
      expect(
        () => AttendancePolicy(earlyWindowMinutes: -1),
        throwsArgumentError,
      );
      expect(() => AttendancePolicy(graceMinutes: -1), throwsArgumentError);
      expect(() => AttendancePolicy(lateUntilMinutes: -1), throwsArgumentError);
      expect(() => AttendancePolicy(lateUntilMinutes: 9), throwsArgumentError);
      for (final accuracy in [0.0, -1.0, double.nan, double.infinity]) {
        expect(
          () => AttendancePolicy(maxAccuracyMeters: accuracy),
          throwsArgumentError,
        );
      }
      expect(
        () => AttendancePolicy().copyWith(earlyWindowMinutes: -1),
        throwsArgumentError,
      );
    },
  );
}
