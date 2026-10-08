import 'package:did_i_attend/src/data/database/tables.dart';
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
    ClassSampleTasks,
  ],
)
final class AppDatabase extends _$AppDatabase {
  AppDatabase()
    : super(
        driftDatabase(
          name: 'did_i_attend',
          native: const DriftNativeOptions(shareAcrossIsolates: true),
        ),
      );

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    onUpgrade: (migrator, from, to) async {
      if (from == 1 && to == 2) {
        await migrator.createTable(classSampleTasks);
      } else {
        throw UnsupportedError('No migration from schema $from to $to.');
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      // A bounded lock wait is safe for every client of the shared connection.
      await customStatement('PRAGMA busy_timeout = 5000');
    },
  );
}
