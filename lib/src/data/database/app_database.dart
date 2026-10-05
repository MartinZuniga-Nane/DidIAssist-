import 'package:did_i_assist/src/data/database/tables.dart';
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Places,
    Courses,
    ScheduleSlots,
    LocationEvents,
    AttendanceRecords,
    Trips,
    UserSettingsTable,
  ],
)
final class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'did_i_assist'));

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    onUpgrade: (migrator, from, to) async {
      throw UnsupportedError('No migration from schema $from to $to.');
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
