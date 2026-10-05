import 'package:did_i_assist/src/data/database/app_database.dart';
import 'package:did_i_assist/src/data/database/mappers/attendance_record_mapping.dart';
import 'package:did_i_assist/src/data/database/mappers/course_mapping.dart';
import 'package:did_i_assist/src/data/database/mappers/location_event_mapping.dart';
import 'package:did_i_assist/src/data/database/mappers/place_mapping.dart';
import 'package:did_i_assist/src/data/database/mappers/schedule_slot_mapping.dart';
import 'package:did_i_assist/src/data/database/mappers/settings_mapping.dart';
import 'package:did_i_assist/src/data/database/mappers/trip_mapping.dart';
import 'package:did_i_assist/src/domain/models/user_settings.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../domain/models/fixtures.dart';
import 'test_database.dart';

void main() {
  late AppDatabase database;

  setUp(() => database = createTestDatabase());
  tearDown(() => database.close());

  Future<void> seedSchedule() async {
    await database
        .into(database.places)
        .insert(placeToCompanion(samplePlace()));
    await database
        .into(database.courses)
        .insert(courseToCompanion(sampleCourse()));
    await database
        .into(database.scheduleSlots)
        .insert(scheduleSlotToCompanion(sampleSlot()));
  }

  test('creates seven tables at version 1 and enables foreign keys', () async {
    final tables = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
        )
        .get();
    expect(tables.map((row) => row.read<String>('name')), [
      'attendance_records',
      'courses',
      'location_events',
      'places',
      'schedule_slots',
      'trips',
      'user_settings',
    ]);
    expect(database.schemaVersion, 1);
    expect(
      (await database.customSelect('PRAGMA user_version').getSingle())
          .read<int>('user_version'),
      1,
    );
    expect(
      (await database.customSelect('PRAGMA foreign_keys').getSingle())
          .read<int>('foreign_keys'),
      1,
    );
  });

  test(
    'creates required indexes with columns in the specified order',
    () async {
      final indexes = {
        'location_events_recorded_at': ['recorded_at'],
        'location_events_place_recorded_at': ['place_id', 'recorded_at'],
        'attendance_occurrence_date': ['occurrence_date'],
        'trips_pair_arrived_at': ['from_place_id', 'to_place_id', 'arrived_at'],
      };
      for (final entry in indexes.entries) {
        final rows = await database
            .customSelect('PRAGMA index_info(${entry.key})')
            .get();
        expect(rows.map((row) => row.read<String>('name')), entry.value);
      }
    },
  );

  test('slot foreign keys enforce cascade and restrict', () async {
    final rows = await database
        .customSelect('PRAGMA foreign_key_list(schedule_slots)')
        .get();
    final actions = {
      for (final row in rows)
        row.read<String>('from'): row.read<String>('on_delete'),
    };
    expect(actions, {'course_id': 'CASCADE', 'place_id': 'RESTRICT'});
    await seedSchedule();
    await expectLater(
      (database.delete(
        database.places,
      )..where((table) => table.id.equals(placeId))).go(),
      throwsA(isA<Exception>()),
    );
    expect(await database.select(database.places).get(), hasLength(1));
    await (database.delete(
      database.courses,
    )..where((table) => table.id.equals(courseId))).go();
    expect(await database.select(database.scheduleSlots).get(), isEmpty);
    await (database.delete(
      database.places,
    )..where((table) => table.id.equals(placeId))).go();
    expect(await database.select(database.places).get(), isEmpty);
  });

  test('slots reject missing course and place', () async {
    await expectLater(
      database
          .into(database.scheduleSlots)
          .insert(scheduleSlotToCompanion(sampleSlot())),
      throwsA(isA<Exception>()),
    );
    await database
        .into(database.courses)
        .insert(courseToCompanion(sampleCourse()));
    await expectLater(
      database
          .into(database.scheduleSlots)
          .insert(scheduleSlotToCompanion(sampleSlot())),
      throwsA(isA<Exception>()),
    );
    await database
        .into(database.places)
        .insert(placeToCompanion(samplePlace()));
    await (database.delete(
      database.courses,
    )..where((table) => table.id.equals(courseId))).go();
    await expectLater(
      database
          .into(database.scheduleSlots)
          .insert(scheduleSlotToCompanion(sampleSlot())),
      throwsA(isA<Exception>()),
    );
  });

  test('attendance uniqueness is per slot and local date', () async {
    final record = sampleAttendance();
    await database
        .into(database.attendanceRecords)
        .insert(attendanceRecordToCompanion(record));
    await expectLater(
      database
          .into(database.attendanceRecords)
          .insert(
            attendanceRecordToCompanion(record.copyWith(id: 'duplicate')),
          ),
      throwsA(isA<Exception>()),
    );
    await database
        .into(database.attendanceRecords)
        .insert(
          attendanceRecordToCompanion(
            record.copyWith(id: 'other-slot', slotId: 'other-slot'),
          ),
        );
    await database
        .into(database.attendanceRecords)
        .insert(
          attendanceRecordToCompanion(
            record.copyWith(
              id: 'other-date',
              occurrenceDate: record.occurrenceDate.addDays(1),
            ),
          ),
        );
    expect(
      await database.select(database.attendanceRecords).get(),
      hasLength(3),
    );
  });

  test(
    'history has no foreign keys and survives deletion of all parents',
    () async {
      for (final table in ['attendance_records', 'location_events', 'trips']) {
        expect(
          await database.customSelect('PRAGMA foreign_key_list($table)').get(),
          isEmpty,
        );
      }
      await seedSchedule();
      await database
          .into(database.attendanceRecords)
          .insert(attendanceRecordToCompanion(sampleAttendance()));
      await database
          .into(database.locationEvents)
          .insert(locationEventToCompanion(sampleEvent()));
      await database.into(database.trips).insert(tripToCompanion(sampleTrip()));
      await database.delete(database.courses).go();
      await database.delete(database.places).go();
      expect(
        await database.select(database.attendanceRecords).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.locationEvents).get(),
        hasLength(1),
      );
      expect(await database.select(database.trips).get(), hasLength(1));
    },
  );

  test(
    'settings restricts the singleton ID and rejects a second row',
    () async {
      final companion = settingsToCompanion(UserSettings());
      await expectLater(
        database
            .into(database.userSettingsTable)
            .insert(companion.copyWith(id: const Value(2))),
        throwsA(isA<Exception>()),
      );
      await database.into(database.userSettingsTable).insert(companion);
      await expectLater(
        database.into(database.userSettingsTable).insert(companion),
        throwsA(isA<Exception>()),
      );
      expect(
        await database.select(database.userSettingsTable).get(),
        hasLength(1),
      );
    },
  );

  test(
    'instant and date columns use explicit integer and text storage',
    () async {
      await database
          .into(database.locationEvents)
          .insert(locationEventToCompanion(sampleEvent()));
      await database
          .into(database.attendanceRecords)
          .insert(attendanceRecordToCompanion(sampleAttendance()));
      await database.into(database.trips).insert(tripToCompanion(sampleTrip()));
      for (final query in [
        'SELECT typeof(recorded_at) AS value FROM location_events',
        'SELECT typeof(evaluated_at) AS value FROM attendance_records',
        'SELECT typeof(check_in_at) AS value FROM attendance_records',
        'SELECT typeof(departed_at) AS value FROM trips',
        'SELECT typeof(arrived_at) AS value FROM trips',
      ]) {
        expect(
          (await database.customSelect(query).getSingle()).read<String>(
            'value',
          ),
          'integer',
        );
      }
      expect(
        (await database
                .customSelect(
                  'SELECT typeof(occurrence_date) AS value '
                  'FROM attendance_records',
                )
                .getSingle())
            .read<String>('value'),
        'text',
      );
    },
  );
}
