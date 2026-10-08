import 'package:did_i_attend/src/core/local_date.dart';
import 'package:did_i_attend/src/domain/models/attendance_record.dart';

abstract interface class AttendanceRepository {
  Future<AttendanceRecord?> findBySlotAndDate(
    String slotId,
    LocalDate occurrenceDate,
  );

  /// Atomically upserts by (slotId, occurrenceDate).
  /// Returns the stored record.
  ///
  /// Automatic writes must retain any existing manual record. Updates retain
  /// the existing record ID, including when a caller supplies a different ID.
  Future<AttendanceRecord> upsert(AttendanceRecord record);

  /// Returns records in the local date range [from, until), ordered by date.
  Future<List<AttendanceRecord>> query({
    required LocalDate from,
    required LocalDate until,
    String? courseId,
  });

  /// Uses the same half-open date range and ordering as [query].
  Stream<List<AttendanceRecord>> watch({
    required LocalDate from,
    required LocalDate until,
    String? courseId,
  });
}
