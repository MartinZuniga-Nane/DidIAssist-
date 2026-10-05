import 'dart:math' as math;

import 'package:did_i_assist/src/core/geo.dart';
import 'package:did_i_assist/src/domain/models/models.dart';
import 'package:did_i_assist/src/domain/services/attendance_evaluation.dart';

final class AttendanceEvaluator {
  AttendanceEvaluator({this.carryOver = const Duration(hours: 12)}) {
    if (carryOver.isNegative) {
      throw ArgumentError.value(carryOver, 'carryOver', 'Must be nonnegative.');
    }
  }

  /// Age limit for inside confirmations carried into the attendance window.
  final Duration carryOver;

  AttendanceEvaluation evaluate({
    required ClassOccurrence occurrence,
    required Place place,
    required Iterable<LocationEvent> events,
    required AttendancePolicy policy,
    required DateTime now,
  }) {
    if (place.id != occurrence.place.id) {
      throw ArgumentError('place must belong to the occurrence.');
    }
    final start = occurrence.start.toUtc();
    final end = occurrence.end.toUtc();
    final instant = now.toUtc();
    final windowStart = start.subtract(
      Duration(minutes: policy.earlyWindowMinutes),
    );
    if (instant.isBefore(windowStart)) {
      return AttendanceEvaluation(status: AttendanceStatus.pending);
    }
    final historyStart = windowStart.subtract(carryOver);
    final limit = instant.isBefore(end) ? instant : end;
    final signals = <_PresenceSignal>[];
    for (final event in events) {
      if (event.recordedAt.isBefore(historyStart) ||
          event.recordedAt.isAfter(limit)) {
        continue;
      }
      final signal = _signalFor(event, place, policy);
      if (signal != null) signals.add(signal);
    }
    signals.sort(_compareSignals);

    var inside = false;
    DateTime? firstInside;
    for (final signal in signals) {
      // An exit at window start closes the preceding half-open interval.
      if (inside && signal.at.isAfter(windowStart)) {
        firstInside ??= windowStart;
      }
      inside = signal.inside;
      if (inside && !signal.at.isBefore(windowStart)) {
        firstInside ??= signal.at;
      }
    }
    if (inside) firstInside ??= windowStart;

    if (firstInside == null) {
      return AttendanceEvaluation(
        status: instant.isBefore(end)
            ? AttendanceStatus.pending
            : AttendanceStatus.absent,
      );
    }
    final graceEnd = start.add(Duration(minutes: policy.graceMinutes));
    final lateEnd = policy.lateUntilMinutes == null
        ? end
        : start.add(Duration(minutes: policy.lateUntilMinutes!));
    final status = !firstInside.isAfter(graceEnd)
        ? AttendanceStatus.present
        : !firstInside.isAfter(lateEnd)
        ? AttendanceStatus.late
        : AttendanceStatus.absent;
    return AttendanceEvaluation(status: status, checkInAt: firstInside);
  }
}

typedef _PresenceSignal = ({DateTime at, bool inside, int order, String id});

_PresenceSignal? _signalFor(
  LocationEvent event,
  Place place,
  AttendancePolicy policy,
) {
  if (event.type != LocationEventType.positionSample &&
      event.placeId != place.id) {
    return null;
  }
  final bool inside;
  final int order;
  switch (event.type) {
    case LocationEventType.geofenceExit:
      inside = false;
      order = 0;
    case LocationEventType.geofenceEnter:
      inside = true;
      order = 2;
    case LocationEventType.geofenceDwell:
      inside = true;
      order = 3;
    case LocationEventType.positionSample:
      final accuracy = event.accuracyMeters ?? 0;
      if (accuracy > policy.maxAccuracyMeters) return null;
      inside =
          haversineDistanceMeters(event.position!, place.center) <=
          place.radiusMeters + math.min(accuracy, policy.maxAccuracyMeters);
      order = inside ? 4 : 1;
  }
  return (at: event.recordedAt, inside: inside, order: order, id: event.id);
}

/// Exits, outside samples, enters, dwells, inside samples, then event ID.
/// Conflicting evidence at one instant therefore favors confirmed presence.
int _compareSignals(_PresenceSignal first, _PresenceSignal second) {
  final timeOrder = first.at.compareTo(second.at);
  if (timeOrder != 0) return timeOrder;
  final signalOrder = first.order.compareTo(second.order);
  return signalOrder != 0 ? signalOrder : first.id.compareTo(second.id);
}
