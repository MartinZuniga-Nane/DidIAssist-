import 'package:did_i_assist/src/data/database/app_database.dart';
import 'package:did_i_assist/src/data/database/mappers/date_mapping.dart';
import 'package:did_i_assist/src/domain/models/attendance_record.dart';
import 'package:did_i_assist/src/domain/models/attendance_source.dart';
import 'package:did_i_assist/src/domain/models/attendance_status.dart';
import 'package:drift/drift.dart';

AttendanceRecord attendanceRecordFromRow(AttendanceRecordRow row) =>
    AttendanceRecord(
      id: row.id,
      slotId: row.slotId,
      courseId: row.courseId,
      occurrenceDate: localDateFromText(row.occurrenceDate),
      status: AttendanceStatus.values.byName(row.status),
      source: AttendanceSource.values.byName(row.source),
      checkInAt: row.checkInAt == null
          ? null
          : instantFromMilliseconds(row.checkInAt!),
      evaluatedAt: instantFromMilliseconds(row.evaluatedAt),
    );

AttendanceRecordsCompanion attendanceRecordToCompanion(
  AttendanceRecord record,
) => AttendanceRecordsCompanion.insert(
  id: record.id,
  slotId: record.slotId,
  courseId: record.courseId,
  occurrenceDate: localDateToText(record.occurrenceDate),
  status: record.status.name,
  source: record.source.name,
  checkInAt: Value(
    record.checkInAt == null ? null : instantToMilliseconds(record.checkInAt!),
  ),
  evaluatedAt: instantToMilliseconds(record.evaluatedAt),
);
