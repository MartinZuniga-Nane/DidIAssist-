import 'dart:async';

import 'package:did_i_assist/src/app/app_error_handler.dart';
import 'package:did_i_assist/src/app/app_services.dart';
import 'package:did_i_assist/src/app/open_app_services.dart';
import 'package:did_i_assist/src/app/schedule_change_coordinator.dart';
import 'package:did_i_assist/src/app/start_background_work.dart';
import 'package:did_i_assist/src/domain/repositories/notification_gateway.dart';
import 'package:did_i_assist/src/platform/notifications/create_notification_gateway.dart';
import 'package:did_i_assist/src/platform/notifications/lazy_notification_gateway.dart';
import 'package:flutter/widgets.dart';

final class AppStartup with WidgetsBindingObserver {
  AppStartup({
    Future<NotificationGateway> Function() createNotifications =
        createNotificationGateway,
    Future<AppServices> Function(NotificationGateway) openServices =
        _openServices,
    Future<void> Function(AppServices)? startWork,
    void Function(Object, StackTrace) onError = reportAppError,
  }) : _createNotifications = createNotifications,
       _open = openServices,
       _startWork = startWork,
       _onError = onError;

  static Future<AppServices> _openServices(NotificationGateway notifications) =>
      openAppServices(notifications: notifications);

  final Future<NotificationGateway> Function() _createNotifications;
  final Future<AppServices> Function(NotificationGateway) _open;
  final Future<void> Function(AppServices)? _startWork;
  final void Function(Object, StackTrace) _onError;
  AppServices? _services;
  ScheduleChangeCoordinator? _coordinator;
  Future<void>? _initialization;
  Future<void>? _closing;
  bool _launched = false;
  bool _disposed = false;

  AppServices? get services => _services;

  void launch(Widget app) {
    if (_launched || _disposed) {
      throw StateError('Startup cannot be relaunched.');
    }
    _launched = true;
    final binding = WidgetsFlutterBinding.ensureInitialized()
      ..addObserver(this);
    runApp(app);
    binding.addPostFrameCallback((_) => unawaited(initialize()));
  }

  Future<void> initialize() {
    if (_disposed) return Future<void>.value();
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    WidgetsFlutterBinding.ensureInitialized();
    final notifications = LazyNotificationGateway(_createNotifications);
    // Initialization never prompts; a denied grant still opens the backend.
    await _attempt(() async {
      await notifications.ensurePermission();
    });
    if (_disposed) return;
    try {
      _services = await _open(notifications);
    } on Object catch (error, stackTrace) {
      _onError(error, stackTrace);
      return;
    }
    final services = _services!;
    if (_disposed) return;
    await _attempt(() async {
      if (_startWork case final start?) {
        await start(services);
      } else {
        await startBackgroundWork(services, onError: _onError);
      }
    });
    if (_disposed) return;
    await _attempt(() async {
      await services.reminderService.reconcile();
    });
    if (_disposed) return;
    _coordinator = ScheduleChangeCoordinator(
      places: services.places,
      courses: services.courses,
      settings: services.settings,
      syncGeofences: services.syncGeofencesWhenPermitted,
      syncClassSamples: services.syncClassSamplesWhenPermitted,
      reconcileReminders: () async {
        await services.reminderService.reconcile();
      },
      onError: _onError,
    );
    await _attempt(() async => _coordinator!.start());
  }

  Future<void> _attempt(Future<void> Function() action) async {
    try {
      await action();
    } on Object catch (error, stackTrace) {
      _onError(error, stackTrace);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) unawaited(dispose());
  }

  Future<void> dispose() => _closing ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    if (_launched) WidgetsBinding.instance.removeObserver(this);
    await _initialization;
    await _attempt(() async => _coordinator?.dispose());
    await _attempt(() async => _services?.dispose());
  }
}
