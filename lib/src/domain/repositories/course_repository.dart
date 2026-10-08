import 'package:did_i_attend/src/domain/models/course.dart';
import 'package:did_i_attend/src/domain/models/schedule_slot.dart';

abstract interface class CourseRepository {
  Future<Course?> getById(String id);
  Future<List<Course>> getAll();
  Stream<List<Course>> watchAll();
  Future<void> saveCourse(Course course);

  /// Deletes the course and its weekly slots; preserves attendance history.
  Future<void> deleteCourse(String id);

  Future<List<ScheduleSlot>> getSlots({String? courseId});
  Stream<List<ScheduleSlot>> watchSlots({String? courseId});
  Future<void> saveSlot(ScheduleSlot slot);

  /// Preserves attendance history for the deleted slot.
  Future<void> deleteSlot(String id);
}
