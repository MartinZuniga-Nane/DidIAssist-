import 'package:did_i_assist/src/data/database/app_database.dart';
import 'package:did_i_assist/src/domain/models/schedule_slot.dart';

ScheduleSlot scheduleSlotFromRow(ScheduleSlotRow row) => ScheduleSlot(
  id: row.id,
  courseId: row.courseId,
  placeId: row.placeId,
  weekday: row.weekday,
  startMinute: row.startMinute,
  durationMinutes: row.durationMinutes,
);

ScheduleSlotsCompanion scheduleSlotToCompanion(ScheduleSlot slot) =>
    ScheduleSlotsCompanion.insert(
      id: slot.id,
      courseId: slot.courseId,
      placeId: slot.placeId,
      weekday: slot.weekday,
      startMinute: slot.startMinute,
      durationMinutes: slot.durationMinutes,
    );
