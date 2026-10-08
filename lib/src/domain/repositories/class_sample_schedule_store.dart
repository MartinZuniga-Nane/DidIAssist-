import 'package:did_i_attend/src/domain/services/class_sample_planner.dart';

abstract interface class ClassSampleScheduleStore {
  Future<T> synchronized<T>(Future<T> Function() action);
  Future<List<ClassSampleTask>> load();
  Future<void> save(ClassSampleTask task);
  Future<void> delete(String uniqueName);
}
