import 'package:did_i_assist/src/domain/location/position_fix.dart';

enum PositionFailureReason { timeout, permissionDenied, serviceDisabled }

final class PositionUnavailable implements Exception {
  const PositionUnavailable(this.reason);

  final PositionFailureReason reason;

  @override
  String toString() => 'PositionUnavailable(${reason.name})';
}

abstract interface class PositionProvider {
  /// Expected location failures throw [PositionUnavailable].
  Future<PositionFix> currentFix({
    Duration timeout = const Duration(seconds: 30),
  });

  Future<PositionFix?> lastKnownFix();
}
