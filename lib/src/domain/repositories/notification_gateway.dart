import 'package:did_i_attend/src/domain/models/planned_notification.dart';

enum NotificationPermission { granted, denied, unavailable }

abstract interface class NotificationGateway {
  /// Checks authorization without displaying a permission prompt.
  Future<NotificationPermission> ensurePermission();
  Future<NotificationPermission> requestPermission();
  Future<void> schedule(PlannedNotification notification);
  Future<void> show(PlannedNotification notification);
  Future<void> cancel(int id);

  /// Only notifications carrying this application's recognized payload.
  Future<List<PlannedNotification>> pendingNotifications();

  /// Includes unrelated notifications so their IDs are never reused.
  Future<Set<int>> pendingIds();
  Future<int> cancelWhere(bool Function(PlannedNotification) predicate);
}
