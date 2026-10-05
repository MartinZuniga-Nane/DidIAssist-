import 'package:did_i_assist/src/data/database/app_database.dart';
import 'package:did_i_assist/src/data/database/mappers/date_mapping.dart';
import 'package:did_i_assist/src/domain/repositories/class_sample_schedule_store.dart';
import 'package:did_i_assist/src/domain/services/class_sample_planner.dart';
import 'package:drift/drift.dart';

final class DriftClassSampleScheduleStore implements ClassSampleScheduleStore {
  const DriftClassSampleScheduleStore(this._database);

  final AppDatabase _database;

  @override
  Future<T> synchronized<T>(Future<T> Function() action) =>
      _database.transaction(action);

  @override
  Future<List<ClassSampleTask>> load() async =>
      (await (_database.select(
            _database.classSampleTasks,
          )..orderBy([(table) => OrderingTerm.asc(table.uniqueName)])).get())
          .map(
            (row) => ClassSampleTask(
              slotId: row.slotId,
              date: localDateFromText(row.occurrenceDate),
              offsetMinutes: row.offsetMinutes,
              classStart: instantFromMilliseconds(row.classStart),
              runAt: instantFromMilliseconds(row.runAt),
            ),
          )
          .toList();

  @override
  Future<void> save(ClassSampleTask task) async {
    await _database
        .into(_database.classSampleTasks)
        .insertOnConflictUpdate(
          ClassSampleTasksCompanion.insert(
            uniqueName: task.uniqueName,
            slotId: task.slotId,
            occurrenceDate: localDateToText(task.date),
            offsetMinutes: task.offsetMinutes,
            classStart: instantToMilliseconds(task.classStart),
            runAt: instantToMilliseconds(task.runAt),
          ),
        );
  }

  @override
  Future<void> delete(String uniqueName) async {
    await (_database.delete(
      _database.classSampleTasks,
    )..where((table) => table.uniqueName.equals(uniqueName))).go();
  }
}
