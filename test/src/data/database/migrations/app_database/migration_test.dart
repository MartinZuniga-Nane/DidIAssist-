import 'package:did_i_assist/src/data/database/app_database.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_database.dart';
import 'generated/schema.dart';

void main() {
  late SchemaVerifier verifier;

  setUp(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('fresh database matches the exported schema version', () async {
    final database = createTestDatabase();
    addTearDown(database.close);
    expect(GeneratedHelper.versions.last, database.schemaVersion);
    await verifier.migrateAndValidate(database, database.schemaVersion);
  });

  test(
    'v1 upgrade preserves all existing data while adding the task ledger',
    () async {
      final schema = await verifier.schemaAt(1);
      addTearDown(schema.rawDatabase.dispose);
      schema.rawDatabase
        ..execute(
          'INSERT INTO places VALUES (?, ?, ?, ?, ?, ?)',
          ['campus', 'Campus', 'campus', 48.8606, 2.3376, 150.0],
        )
        ..execute('INSERT INTO courses VALUES (?, ?, ?, ?)', [
          'course',
          'Math',
          null,
          null,
        ])
        ..execute('INSERT INTO schedule_slots VALUES (?, ?, ?, ?, ?, ?)', [
          'slot',
          'course',
          'campus',
          1,
          540,
          90,
        ])
        ..execute('INSERT INTO location_events VALUES (?, ?, ?, ?, ?, ?, ?)', [
          'event',
          'geofenceEnter',
          'campus',
          null,
          null,
          null,
          123,
        ])
        ..execute(
          'INSERT INTO attendance_records VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
          [
            'record',
            'slot',
            'course',
            '2026-10-05',
            'present',
            'manual',
            123,
            456,
          ],
        )
        ..execute('INSERT INTO trips VALUES (?, ?, ?, ?, ?, ?)', [
          'trip',
          'home',
          'campus',
          123,
          456,
          null,
        ])
        ..execute('INSERT INTO user_settings VALUES (?, ?, ?, ?, ?, ?, ?, ?)', [
          1,
          'walking',
          5,
          15,
          10,
          null,
          200.0,
          1,
        ]);
      final database = AppDatabase.forTesting(schema.newConnection());
      addTearDown(database.close);
      await verifier.migrateAndValidate(database, 2);
      for (final table in [
        'places',
        'courses',
        'schedule_slots',
        'location_events',
        'attendance_records',
        'trips',
        'user_settings',
      ]) {
        expect(
          (await database
                  .customSelect('SELECT COUNT(*) AS count FROM $table')
                  .getSingle())
              .read<int>('count'),
          1,
        );
      }
      expect(await database.select(database.classSampleTasks).get(), isEmpty);
      final attendance = await database
          .select(database.attendanceRecords)
          .getSingle();
      expect(attendance.source, 'manual');
      expect(attendance.checkInAt, 123);
      expect(attendance.evaluatedAt, 456);
      expect(
        (await database.customSelect('PRAGMA busy_timeout').getSingle())
            .read<int>('timeout'),
        5000,
      );
    },
  );

  for (final (index, from) in GeneratedHelper.versions.indexed) {
    for (final to in GeneratedHelper.versions.skip(index)) {
      test('schema $from opens and migrates to $to', () async {
        final schema = await verifier.schemaAt(from);
        addTearDown(schema.rawDatabase.dispose);
        final database = AppDatabase.forTesting(schema.newConnection());
        addTearDown(database.close);
        await verifier.migrateAndValidate(database, to);
        expect(
          (await database.customSelect('PRAGMA foreign_keys').getSingle())
              .read<int>('foreign_keys'),
          1,
        );
      });
    }
  }
}
