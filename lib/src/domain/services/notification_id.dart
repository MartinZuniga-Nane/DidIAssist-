import 'dart:convert';

import 'package:did_i_attend/src/core/local_date.dart';
import 'package:did_i_attend/src/domain/models/model_validation.dart';
import 'package:did_i_attend/src/domain/models/planned_notification.dart';

int notificationId({
  required NotificationKind kind,
  required String slotId,
  required LocalDate occurrenceDate,
}) {
  requireNonBlank(slotId, 'slotId');
  final date = notificationDateKey(occurrenceDate);
  final key = '${kind.name}:${utf8.encode(slotId).length}:$slotId:$date';
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(key)) {
    hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
  }
  // Separate kinds into disjoint ranges inside Android's signed 31-bit IDs.
  return (hash & 0x3fffffff) |
      (kind == NotificationKind.attendanceResult ? 0x40000000 : 0);
}

String notificationDateKey(LocalDate date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
