import 'package:did_i_assist/src/app/app_error_handler.dart';
import 'package:did_i_assist/src/app/app_services.dart';
import 'package:did_i_assist/src/platform/background/background_scheduler.dart';

Future<void> startBackgroundWork(
  AppServices services, {
  BackgroundScheduler? scheduler,
  void Function(Object, StackTrace) onError = reportAppError,
}) async {
  for (final action in [
    services.syncGeofencesWhenPermitted,
    (scheduler ?? BackgroundScheduler()).initialize,
    services.syncClassSamplesWhenPermitted,
  ]) {
    try {
      await action();
    } on Object catch (error, stackTrace) {
      onError(error, stackTrace);
    }
  }
}
