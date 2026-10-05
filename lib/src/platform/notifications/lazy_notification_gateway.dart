import 'package:did_i_assist/src/domain/models/planned_notification.dart';
import 'package:did_i_assist/src/domain/repositories/notification_gateway.dart';

/// Defers platform setup until after evidence has been persisted.
final class LazyNotificationGateway implements NotificationGateway {
  LazyNotificationGateway(this._create);

  final Future<NotificationGateway> Function() _create;
  Future<NotificationGateway>? _opening;

  Future<NotificationGateway> _gateway() async {
    try {
      return await (_opening ??= _create());
    } on Object {
      _opening = null;
      rethrow;
    }
  }

  @override
  Future<NotificationPermission> ensurePermission() async =>
      (await _gateway()).ensurePermission();

  @override
  Future<NotificationPermission> requestPermission() async =>
      (await _gateway()).requestPermission();

  @override
  Future<void> schedule(PlannedNotification notification) async =>
      (await _gateway()).schedule(notification);

  @override
  Future<void> show(PlannedNotification notification) async =>
      (await _gateway()).show(notification);

  @override
  Future<void> cancel(int id) async => (await _gateway()).cancel(id);

  @override
  Future<List<PlannedNotification>> pendingNotifications() async =>
      (await _gateway()).pendingNotifications();

  @override
  Future<Set<int>> pendingIds() async => (await _gateway()).pendingIds();

  @override
  Future<int> cancelWhere(bool Function(PlannedNotification) predicate) async =>
      (await _gateway()).cancelWhere(predicate);
}
