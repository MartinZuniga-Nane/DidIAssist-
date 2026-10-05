import 'package:clock/clock.dart';
import 'package:did_i_assist/src/domain/models/planned_notification.dart';
import 'package:did_i_assist/src/domain/repositories/notification_gateway.dart';
import 'package:did_i_assist/src/platform/notifications/notification_message_builder.dart';
import 'package:did_i_assist/src/platform/notifications/notification_payload_codec.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

final class LocalNotificationsGateway implements NotificationGateway {
  LocalNotificationsGateway({
    required NotificationMessageBuilder messageBuilder,
    FlutterLocalNotificationsPlugin? plugin,
    Future<String> Function()? timezoneName,
    Clock? timeSource,
  }) : _messages = messageBuilder,
       _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _timezoneName = timezoneName ?? FlutterTimezone.getLocalTimezone,
       _clock = timeSource ?? clock;

  static const departureChannelId = 'departure_reminders';
  static const attendanceChannelId = 'attendance_results';

  final NotificationMessageBuilder _messages;
  final FlutterLocalNotificationsPlugin _plugin;
  final Future<String> Function() _timezoneName;
  final Clock _clock;
  final NotificationPayloadCodec _codec = const NotificationPayloadCodec();
  Future<void>? _initialization;
  late tz.Location _location;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  IOSFlutterLocalNotificationsPlugin? get _ios => _plugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >();

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    tz_data.initializeTimeZones();
    _location = tz.getLocation(await _timezoneName());
    tz.setLocalLocation(_location);
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    final strings = _messages.strings;
    await _android?.createNotificationChannel(
      AndroidNotificationChannel(
        departureChannelId,
        strings.departureChannelName,
        description: strings.departureChannelDescription,
        importance: Importance.high,
      ),
    );
    await _android?.createNotificationChannel(
      AndroidNotificationChannel(
        attendanceChannelId,
        strings.attendanceChannelName,
        description: strings.attendanceChannelDescription,
      ),
    );
  }

  @override
  Future<NotificationPermission> ensurePermission() async {
    await initialize();
    if (_android case final android?) {
      return _permission(await android.areNotificationsEnabled());
    }
    if (_ios case final ios?) {
      return _permission((await ios.checkPermissions())?.isEnabled);
    }
    return NotificationPermission.unavailable;
  }

  @override
  Future<NotificationPermission> requestPermission() async {
    await initialize();
    if (_android case final android?) {
      return _permission(await android.requestNotificationsPermission());
    }
    if (_ios case final ios?) {
      return _permission(
        await ios.requestPermissions(alert: true, badge: true, sound: true),
      );
    }
    return NotificationPermission.unavailable;
  }

  NotificationPermission _permission(bool? granted) => switch (granted) {
    true => NotificationPermission.granted,
    false => NotificationPermission.denied,
    null => NotificationPermission.unavailable,
  };

  NotificationDetails _details(NotificationKind kind) {
    final departure = kind == NotificationKind.departureReminder;
    final strings = _messages.strings;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        departure ? departureChannelId : attendanceChannelId,
        departure
            ? strings.departureChannelName
            : strings.attendanceChannelName,
        channelDescription: departure
            ? strings.departureChannelDescription
            : strings.attendanceChannelDescription,
        importance: departure ? Importance.high : Importance.defaultImportance,
        priority: departure ? Priority.high : Priority.defaultPriority,
        icon: 'ic_notification',
      ),
      iOS: const DarwinNotificationDetails(),
    );
  }

  @override
  Future<void> schedule(PlannedNotification notification) async {
    await initialize();
    if (!notification.at.isAfter(_clock.now())) {
      throw ArgumentError.value(
        notification.at,
        'at',
        'Must be in the future.',
      );
    }
    final message = _messages.build(notification);
    final exactAllowed = await _android?.canScheduleExactNotifications();
    await _plugin.zonedSchedule(
      notification.id,
      message.title,
      message.body,
      tz.TZDateTime.from(notification.at, _location),
      _details(notification.kind),
      androidScheduleMode: (exactAllowed ?? false)
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      payload: _codec.encode(notification),
    );
  }

  @override
  Future<void> show(PlannedNotification notification) async {
    await initialize();
    final message = _messages.build(notification);
    await _plugin.show(
      notification.id,
      message.title,
      message.body,
      _details(notification.kind),
      payload: _codec.encode(notification),
    );
  }

  @override
  Future<void> cancel(int id) async {
    await initialize();
    await _plugin.cancel(id);
  }

  @override
  Future<List<PlannedNotification>> pendingNotifications() async {
    await initialize();
    final requests = await _plugin.pendingNotificationRequests();
    return List.unmodifiable([
      for (final request in requests)
        if (_codec.decode(request.id, request.payload) case final notification?)
          notification,
    ]);
  }

  @override
  Future<Set<int>> pendingIds() async {
    await initialize();
    return Set.unmodifiable({
      for (final request in await _plugin.pendingNotificationRequests())
        request.id,
    });
  }

  @override
  Future<int> cancelWhere(bool Function(PlannedNotification) predicate) async {
    final matches = (await pendingNotifications()).where(predicate).toList();
    for (final notification in matches) {
      await cancel(notification.id);
    }
    return matches.length;
  }
}
