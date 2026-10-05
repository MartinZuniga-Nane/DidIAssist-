import 'package:did_i_assist/src/domain/models/model_validation.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

@immutable
final class AttendancePolicy extends Equatable {
  AttendancePolicy({
    this.earlyWindowMinutes = 15,
    this.graceMinutes = 10,
    this.lateUntilMinutes,
    this.maxAccuracyMeters = 200,
  }) {
    requireNonNegative(earlyWindowMinutes, 'earlyWindowMinutes');
    requireNonNegative(graceMinutes, 'graceMinutes');
    if (lateUntilMinutes != null) {
      requireNonNegative(lateUntilMinutes!, 'lateUntilMinutes');
      if (lateUntilMinutes! < graceMinutes) {
        throw ArgumentError('lateUntilMinutes must not precede graceMinutes.');
      }
    }
    requirePositiveFinite(maxAccuracyMeters, 'maxAccuracyMeters');
  }

  final int earlyWindowMinutes;
  final int graceMinutes;

  /// Minutes after class start; null means the class end.
  final int? lateUntilMinutes;
  final double maxAccuracyMeters;

  AttendancePolicy copyWith({
    int? earlyWindowMinutes,
    int? graceMinutes,
    int? Function()? lateUntilMinutes,
    double? maxAccuracyMeters,
  }) => AttendancePolicy(
    earlyWindowMinutes: earlyWindowMinutes ?? this.earlyWindowMinutes,
    graceMinutes: graceMinutes ?? this.graceMinutes,
    lateUntilMinutes: lateUntilMinutes == null
        ? this.lateUntilMinutes
        : lateUntilMinutes(),
    maxAccuracyMeters: maxAccuracyMeters ?? this.maxAccuracyMeters,
  );

  @override
  List<Object?> get props => [
    earlyWindowMinutes,
    graceMinutes,
    lateUntilMinutes,
    maxAccuracyMeters,
  ];
}
