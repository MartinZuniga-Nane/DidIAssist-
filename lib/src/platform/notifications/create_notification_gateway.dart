import 'dart:ui';

import 'package:clock/clock.dart';
import 'package:did_i_assist/src/platform/notifications/local_notifications_gateway.dart';
import 'package:did_i_assist/src/platform/notifications/notification_message_builder.dart';

Future<LocalNotificationsGateway> createNotificationGateway({
  Locale? locale,
  Clock? timeSource,
}) async => LocalNotificationsGateway(
  messageBuilder: await NotificationMessageBuilder.create(
    locale ?? PlatformDispatcher.instance.locale,
  ),
  timeSource: timeSource,
);
