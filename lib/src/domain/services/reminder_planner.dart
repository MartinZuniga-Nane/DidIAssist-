import 'package:did_i_assist/src/domain/models/class_occurrence.dart';
import 'package:did_i_assist/src/domain/models/planned_notification.dart';
import 'package:did_i_assist/src/domain/models/user_settings.dart';
import 'package:did_i_assist/src/domain/services/departure_advisor.dart';
import 'package:did_i_assist/src/domain/services/notification_id.dart';

final class ReminderPlanner {
  const ReminderPlanner();

  List<PlannedNotification> plan({
    required Map<ClassOccurrence, DepartureAdvice> departures,
    required UserSettings settings,
    required DateTime now,
  }) {
    if (!settings.notificationsEnabled) return const [];
    final planned = <PlannedNotification>[];
    final ids = <int>{};
    for (final entry in departures.entries) {
      final occurrence = entry.key;
      final advice = entry.value;
      if (advice.status != DepartureStatus.onTime ||
          !advice.leaveBy.isAfter(now) ||
          !occurrence.start.isAfter(now)) {
        continue;
      }
      final id = notificationId(
        kind: NotificationKind.departureReminder,
        slotId: occurrence.slot.id,
        occurrenceDate: occurrence.occurrenceDate,
      );
      if (!ids.add(id)) {
        throw StateError('Duplicate notification ID in reminder plan.');
      }
      planned.add(
        PlannedNotification(
          id: id,
          kind: NotificationKind.departureReminder,
          at: advice.leaveBy,
          payload: {
            'slotId': occurrence.slot.id,
            'occurrenceDate': notificationDateKey(occurrence.occurrenceDate),
            'courseName': occurrence.course.name,
            'placeName': occurrence.place.name,
            'etaMinutes':
                (advice.eta.duration.inMicroseconds /
                        Duration.microsecondsPerMinute)
                    .ceil()
                    .toString(),
          },
        ),
      );
    }
    planned.sort((a, b) {
      final timeOrder = a.at.compareTo(b.at);
      return timeOrder != 0 ? timeOrder : a.id.compareTo(b.id);
    });
    return List.unmodifiable(planned);
  }
}
