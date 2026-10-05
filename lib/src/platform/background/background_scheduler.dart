import 'package:did_i_assist/src/platform/background/background_task_names.dart';
import 'package:did_i_assist/src/platform/background/callback_dispatcher.dart';
import 'package:workmanager/workmanager.dart';

final class BackgroundScheduler {
  BackgroundScheduler({Workmanager? manager})
    : _manager = manager ?? Workmanager();

  final Workmanager _manager;
  Future<void>? _initialization;

  Future<void> initialize() async {
    try {
      await (_initialization ??= _initialize());
    } catch (_) {
      _initialization = null;
      rethrow;
    }
  }

  Future<void> _initialize() async {
    await _manager.initialize(callbackDispatcher);
    // BGTaskScheduler uses this delay as a hint; region monitoring handles
    // time-sensitive evidence on iOS.
    await _manager.registerPeriodicTask(
      BackgroundTaskNames.periodic,
      BackgroundTaskNames.periodic,
      frequency: const Duration(minutes: 30),
      flexInterval: const Duration(minutes: 5),
      initialDelay: const Duration(minutes: 30),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      constraints: Constraints(
        networkType: NetworkType.notRequired,
        requiresBatteryNotLow: true,
        requiresStorageNotLow: true,
      ),
    );
  }
}
