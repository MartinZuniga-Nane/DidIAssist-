import 'package:did_i_assist/src/app/app_services.dart';
import 'package:did_i_assist/src/platform/background/background_scheduler.dart';

Future<void> startBackgroundWork(
  AppServices services, {
  BackgroundScheduler? scheduler,
}) async {
  await services.geofenceSync.sync();
  await (scheduler ?? BackgroundScheduler()).initialize();
  await services.classSampleScheduler.sync();
}
