import 'package:drift/drift.dart';

@DataClassName('PlaceRow')
class Places extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get kind => text()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  RealColumn get radiusMeters => real()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('CourseRow')
class Courses extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get activeFrom => text().nullable()();
  TextColumn get activeUntil => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ScheduleSlotRow')
class ScheduleSlots extends Table {
  TextColumn get id => text()();
  TextColumn get courseId =>
      text().references(Courses, #id, onDelete: KeyAction.cascade)();
  TextColumn get placeId =>
      text().references(Places, #id, onDelete: KeyAction.restrict)();
  IntColumn get weekday => integer()();
  IntColumn get startMinute => integer()();
  IntColumn get durationMinutes => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex.sql(
  'CREATE INDEX location_events_recorded_at ON location_events (recorded_at)',
)
@TableIndex.sql(
  'CREATE INDEX location_events_place_recorded_at '
  'ON location_events (place_id, recorded_at)',
)
@DataClassName('LocationEventRow')
class LocationEvents extends Table {
  TextColumn get id => text()();
  TextColumn get type => text()();
  TextColumn get placeId => text().nullable()();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  RealColumn get accuracyMeters => real().nullable()();
  // All instant columns store UTC epoch milliseconds, including before 1970.
  IntColumn get recordedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@TableIndex.sql(
  'CREATE INDEX attendance_occurrence_date '
  'ON attendance_records (occurrence_date)',
)
@DataClassName('AttendanceRecordRow')
class AttendanceRecords extends Table {
  TextColumn get id => text()();
  TextColumn get slotId => text()();
  TextColumn get courseId => text()();
  TextColumn get occurrenceDate => text()();
  TextColumn get status => text()();
  TextColumn get source => text()();
  IntColumn get checkInAt => integer().nullable()();
  IntColumn get evaluatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {slotId, occurrenceDate},
  ];
}

@TableIndex.sql(
  'CREATE INDEX trips_pair_arrived_at '
  'ON trips (from_place_id, to_place_id, arrived_at)',
)
@DataClassName('TripRow')
class Trips extends Table {
  TextColumn get id => text()();
  TextColumn get fromPlaceId => text()();
  TextColumn get toPlaceId => text()();
  IntColumn get departedAt => integer()();
  IntColumn get arrivedAt => integer()();
  TextColumn get mode => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('UserSettingsRow')
class UserSettingsTable extends Table {
  @override
  String get tableName => 'user_settings';

  IntColumn get id => integer().customConstraint('NOT NULL CHECK (id = 1)')();
  TextColumn get defaultTravelMode => text()();
  IntColumn get departureBufferMinutes => integer()();
  IntColumn get earlyWindowMinutes => integer()();
  IntColumn get graceMinutes => integer()();
  IntColumn get lateUntilMinutes => integer().nullable()();
  RealColumn get maxAccuracyMeters => real()();
  BoolColumn get notificationsEnabled => boolean()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('ClassSampleTaskRow')
class ClassSampleTasks extends Table {
  TextColumn get uniqueName => text()();
  TextColumn get slotId => text()();
  TextColumn get occurrenceDate => text()();
  IntColumn get offsetMinutes => integer()();
  IntColumn get classStart => integer()();
  IntColumn get runAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {uniqueName};
}
