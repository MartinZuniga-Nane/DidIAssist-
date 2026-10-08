import 'dart:async';

import 'package:did_i_attend/src/domain/location/position_fix.dart';
import 'package:did_i_attend/src/domain/location/position_provider.dart';
import 'package:did_i_attend/src/domain/models/location_event.dart';
import 'package:did_i_attend/src/domain/services/location_event_recorder.dart';
import 'package:equatable/equatable.dart';

sealed class PositionSampleResult extends Equatable {
  const PositionSampleResult();
}

final class PositionSampleRecorded extends PositionSampleResult {
  const PositionSampleRecorded(this.event);

  final LocationEvent event;

  @override
  List<Object> get props => [event];
}

final class PositionSampleFailed extends PositionSampleResult {
  const PositionSampleFailed(this.reason);

  final PositionFailureReason reason;

  @override
  List<Object> get props => [reason];
}

final class PositionSampler {
  const PositionSampler({
    required PositionProvider positionProvider,
    required LocationEventRecorder recorder,
  }) : _provider = positionProvider,
       _recorder = recorder;

  final PositionProvider _provider;
  final LocationEventRecorder _recorder;

  Future<PositionSampleResult> sample({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'Must be positive.');
    }
    final PositionFix fix;
    try {
      fix = await _provider.currentFix(timeout: timeout).timeout(timeout);
    } on PositionUnavailable catch (failure) {
      return PositionSampleFailed(failure.reason);
    } on TimeoutException {
      return const PositionSampleFailed(PositionFailureReason.timeout);
    }
    // Persistence failures are not location failures and must reach the caller.
    return PositionSampleRecorded(await _recorder.recordPositionSample(fix));
  }
}
