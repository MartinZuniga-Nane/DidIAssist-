import 'package:did_i_attend/src/data/database/app_database.dart';
import 'package:did_i_attend/src/data/database/mappers/course_mapping.dart';
import 'package:did_i_attend/src/data/database/mappers/schedule_slot_mapping.dart';
import 'package:did_i_attend/src/data/database/tables.dart';
import 'package:did_i_attend/src/domain/models/course.dart';
import 'package:did_i_attend/src/domain/models/schedule_slot.dart';
import 'package:did_i_attend/src/domain/repositories/course_repository.dart';
import 'package:drift/drift.dart';

final class DriftCourseRepository implements CourseRepository {
  DriftCourseRepository(this._database);

  final AppDatabase _database;

  @override
  Future<Course?> getById(String id) async {
    final row = await (_database.select(
      _database.courses,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    return row == null ? null : courseFromRow(row);
  }

  SimpleSelectStatement<Courses, CourseRow> _all() =>
      _database.select(_database.courses)..orderBy([
        (table) => OrderingTerm.asc(table.name),
        (table) => OrderingTerm.asc(table.id),
      ]);

  @override
  Future<List<Course>> getAll() => _all().map(courseFromRow).get();

  @override
  Stream<List<Course>> watchAll() => _all().map(courseFromRow).watch();

  @override
  Future<void> saveCourse(Course course) async {
    await _database
        .into(_database.courses)
        .insertOnConflictUpdate(
          courseToCompanion(course),
        );
  }

  @override
  Future<void> deleteCourse(String id) async {
    await (_database.delete(
      _database.courses,
    )..where((table) => table.id.equals(id))).go();
  }

  SimpleSelectStatement<ScheduleSlots, ScheduleSlotRow> _slots(
    String? courseId,
  ) {
    final query = _database.select(_database.scheduleSlots);
    if (courseId != null) {
      query.where((table) => table.courseId.equals(courseId));
    }
    return query..orderBy([
      (table) => OrderingTerm.asc(table.weekday),
      (table) => OrderingTerm.asc(table.startMinute),
      (table) => OrderingTerm.asc(table.id),
    ]);
  }

  @override
  Future<List<ScheduleSlot>> getSlots({String? courseId}) =>
      _slots(courseId).map(scheduleSlotFromRow).get();

  @override
  Stream<List<ScheduleSlot>> watchSlots({String? courseId}) =>
      _slots(courseId).map(scheduleSlotFromRow).watch();

  @override
  Future<void> saveSlot(ScheduleSlot slot) async {
    await _database
        .into(_database.scheduleSlots)
        .insertOnConflictUpdate(
          scheduleSlotToCompanion(slot),
        );
  }

  @override
  Future<void> deleteSlot(String id) async {
    await (_database.delete(
      _database.scheduleSlots,
    )..where((table) => table.id.equals(id))).go();
  }
}
