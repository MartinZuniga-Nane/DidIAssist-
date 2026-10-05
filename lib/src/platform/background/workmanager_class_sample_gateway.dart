import 'package:clock/clock.dart';
import 'package:did_i_assist/src/data/database/mappers/date_mapping.dart';
import 'package:did_i_assist/src/domain/repositories/class_sample_task_gateway.dart';
import 'package:did_i_assist/src/domain/services/class_sample_planner.dart';
import 'package:did_i_assist/src/platform/background/background_task_names.dart';
import 'package:workmanager/workmanager.dart';

final class WorkmanagerClassSampleGateway implements ClassSampleTaskGateway {
  WorkmanagerClassSampleGateway({Workmanager? manager, Clock? timeSource})
    : _manager = manager ?? Workmanager(),
      _clock = timeSource ?? clock;

  final Workmanager _manager;
  final Clock _clock;

  @override
  Future<void> schedule(
    ClassSampleTask task,
    ClassSampleSchedulePolicy policy,
  ) {
    final delay = task.runAt.difference(_clock.now());
    // iOS cannot guarantee class-time execution or wake a terminated app for
    // these one-off tasks. Region monitoring remains its primary evidence.
    return _manager.registerOneOffTask(
      task.uniqueName,
      BackgroundTaskNames.classSample,
      inputData: {
        'slotId': task.slotId,
        'date': localDateToText(task.date),
        'offsetMinutes': task.offsetMinutes,
      },
      initialDelay: delay.isNegative ? Duration.zero : delay,
      existingWorkPolicy: switch (policy) {
        ClassSampleSchedulePolicy.keep => ExistingWorkPolicy.keep,
        ClassSampleSchedulePolicy.replace => ExistingWorkPolicy.replace,
      },
      constraints: Constraints(networkType: NetworkType.notRequired),
    );
  }

  @override
  Future<void> cancel(String uniqueName) =>
      _manager.cancelByUniqueName(uniqueName);
}
