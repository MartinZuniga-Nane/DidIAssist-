import 'dart:async';

import 'package:did_i_attend/src/domain/models/planned_notification.dart';
import 'package:did_i_attend/src/domain/repositories/notification_gateway.dart';
import 'package:did_i_attend/src/platform/notifications/lazy_notification_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../app/fakes.dart';

void main() {
  test('creation is lazy and shared by concurrent port calls', () async {
    var opens = 0;
    final created = Completer<NotificationGateway>();
    final delegate = FakeNotifications();
    final gateway = LazyNotificationGateway(() {
      opens++;
      return created.future;
    });
    expect(opens, 0);
    final first = gateway.ensurePermission();
    final second = gateway.pendingIds();
    expect(opens, 1);
    created.complete(delegate);
    expect(await first, NotificationPermission.granted);
    expect(await second, isEmpty);
    expect(opens, 1);
  });

  test(
    'failed creation can be retried without losing the platform port',
    () async {
      var opens = 0;
      final delegate = FakeNotifications();
      final gateway = LazyNotificationGateway(() async {
        if (opens++ == 0) throw StateError('plugin unavailable');
        return delegate;
      });
      await expectLater(gateway.ensurePermission(), throwsStateError);
      expect(await gateway.ensurePermission(), NotificationPermission.granted);
      expect(opens, 2);
    },
  );

  test(
    'forwards every notification operation to the initialized port',
    () async {
      final delegate = FakeNotifications();
      final gateway = LazyNotificationGateway(() async => delegate);
      final notification = PlannedNotification(
        id: 1,
        kind: NotificationKind.departureReminder,
        at: DateTime.utc(2026, 10, 5),
      );
      expect(await gateway.requestPermission(), NotificationPermission.granted);
      await gateway.show(notification);
      await gateway.schedule(notification);
      expect(await gateway.pendingNotifications(), [notification]);
      expect(await gateway.pendingIds(), {1});
      expect(await gateway.cancelWhere((item) => item.id == 1), 1);
      await gateway.cancel(2);
      expect(delegate.shown, [notification]);
      expect(delegate.scheduled, [notification]);
      expect(delegate.canceled, [1, 2]);
    },
  );
}
