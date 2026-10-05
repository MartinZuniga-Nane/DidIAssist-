import 'package:did_i_assist/src/app/app_services.dart';
import 'package:did_i_assist/src/data/database/mappers/date_mapping.dart';
import 'package:did_i_assist/src/platform/background/background_task_names.dart';
import 'package:did_i_assist/src/platform/background/open_background_services.dart';
import 'package:workmanager/workmanager.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask(
    dispatchBackgroundTask,
  );
}

Future<bool> dispatchBackgroundTask(
  String task,
  Map<String, dynamic>? inputData, {
  Future<BackgroundTaskServices> Function() openServices =
      openBackgroundServices,
}) async {
  if (task != BackgroundTaskNames.periodic &&
      task != Workmanager.iOSBackgroundTask &&
      task != BackgroundTaskNames.classSample) {
    return true;
  }
  BackgroundTaskServices? services;
  var succeeded = false;
  try {
    if (task == BackgroundTaskNames.classSample) {
      final slotId = inputData?['slotId'];
      final dateText = inputData?['date'];
      if (slotId is! String || slotId.trim().isEmpty || dateText is! String) {
        return true;
      }
      final date = localDateFromText(dateText);
      services = await openServices();
      succeeded = (await services.pipeline.onClassSampleTask(
        slotId,
        date,
      )).succeeded;
    } else {
      services = await openServices();
      succeeded = (await services.pipeline.onPeriodicTick()).succeeded;
    }
  } on Object catch (_) {
    succeeded = false;
  } finally {
    if (services != null) {
      try {
        await services.dispose();
      } on Object catch (_) {
        succeeded = false;
      }
    }
  }
  return succeeded;
}
