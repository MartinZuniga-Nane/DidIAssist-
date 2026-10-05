import 'package:did_i_assist/src/domain/services/class_sample_planner.dart';

abstract interface class ClassSampleTaskGateway {
  Future<void> schedule(ClassSampleTask task, ClassSampleSchedulePolicy policy);
  Future<void> cancel(String uniqueName);
}
