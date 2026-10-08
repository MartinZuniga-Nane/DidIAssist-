import 'package:did_i_attend/src/core/local_date.dart';
import 'package:did_i_attend/src/data/database/app_database.dart';
import 'package:did_i_attend/src/data/database/mappers/attendance_record_mapping.dart';
import 'package:did_i_attend/src/data/database/mappers/date_mapping.dart';
import 'package:did_i_attend/src/data/database/tables.dart';
import 'package:did_i_attend/src/domain/models/attendance_record.dart';
import 'package:did_i_attend/src/domain/models/attendance_source.dart';
import 'package:did_i_attend/src/domain/repositories/attendance_repository.dart';
import 'package:drift/drift.dart';

final class DriftAttendanceRepository implements AttendanceRepository {
  DriftAttendanceRepository(this._database);

  final AppDatabase _database;

  @override
  Future<AttendanceRecord?> findBySlotAndDate(
    String slotId,
    LocalDate occurrenceDate,
  ) async {
    final row =
        await (_database.select(_database.attendanceRecords)..where(
              (table) =>
                  table.slotId.equals(slotId) &
                  table.occurrenceDate.equals(localDateToText(occurrenceDate)),
            ))
            .getSingleOrNull();
    return row == null ? null : attendanceRecordFromRow(row);
  }

  @override
  Future<AttendanceRecord> upsert(AttendanceRecord record) =>
      _database.transaction(() async {
        final existing = await findBySlotAndDate(
          record.slotId,
          record.occurrenceDate,
        );
        if (existing?.source == AttendanceSource.manual &&
            record.source == AttendanceSource.automatic) {
          return existing!;
        }
        if (existing == null) {
          await _database
              .into(_database.attendanceRecords)
              .insert(
                attendanceRecordToCompanion(record),
              );
        } else {
          await (_database.update(
            _database.attendanceRecords,
          )..where((table) => table.id.equals(existing.id))).write(
            attendanceRecordToCompanion(record.copyWith(id: existing.id)),
          );
        }
        return (await findBySlotAndDate(record.slotId, record.occurrenceDate))!;
      });

  SimpleSelectStatement<AttendanceRecords, AttendanceRecordRow> _range({
    required LocalDate from,
    required LocalDate until,
    String? courseId,
  }) {
    final query = _database.select(_database.attendanceRecords)
      ..where(
        (table) =>
            table.occurrenceDate.isBiggerOrEqualValue(localDateToText(from)) &
            table.occurrenceDate.isSmallerThanValue(localDateToText(until)),
      );
    if (courseId != null) {
      query.where((table) => table.courseId.equals(courseId));
    }
    return query..orderBy([
      (table) => OrderingTerm.asc(table.occurrenceDate),
      (table) => OrderingTerm.asc(table.slotId),
      (table) => OrderingTerm.asc(table.id),
    ]);
  }

  @override
  Future<List<AttendanceRecord>> query({
    required LocalDate from,
    required LocalDate until,
    String? courseId,
  }) => _range(
    from: from,
    until: until,
    courseId: courseId,
  ).map(attendanceRecordFromRow).get();

  @override
  Stream<List<AttendanceRecord>> watch({
    required LocalDate from,
    required LocalDate until,
    String? courseId,
  }) => _range(
    from: from,
    until: until,
    courseId: courseId,
  ).map(attendanceRecordFromRow).watch();
}
