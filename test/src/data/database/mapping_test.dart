import 'package:did_i_assist/src/core/local_date.dart';
import 'package:did_i_assist/src/data/database/app_database.dart';
import 'package:did_i_assist/src/data/database/mappers/attendance_record_mapping.dart';
import 'package:did_i_assist/src/data/database/mappers/course_mapping.dart';
import 'package:did_i_assist/src/data/database/mappers/date_mapping.dart';
import 'package:did_i_assist/src/data/database/mappers/location_event_mapping.dart';
import 'package:did_i_assist/src/data/database/mappers/place_mapping.dart';
import 'package:did_i_assist/src/data/database/mappers/schedule_slot_mapping.dart';
import 'package:did_i_assist/src/data/database/mappers/settings_mapping.dart';
import 'package:did_i_assist/src/data/database/mappers/trip_mapping.dart';
import 'package:did_i_assist/src/domain/models/models.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../domain/models/fixtures.dart';
import 'test_database.dart';

void main() {
  late AppDatabase database;

  setUp(() => database = createTestDatabase());
  tearDown(() => database.close());

  for (final kind in PlaceKind.values) {
    test('place round trip stores ${kind.name} and real coordinates', () async {
      final place = samplePlace().copyWith(kind: kind, radiusMeters: 234.567);
      await database.into(database.places).insert(placeToCompanion(place));
      final row = await database.select(database.places).getSingle();
      expect(placeFromRow(row), place);
      expect(row.kind, kind.name);
      final types = await database
          .customSelect(
            'SELECT typeof(latitude) AS latitude, '
            'typeof(longitude) AS longitude, '
            'typeof(radius_meters) AS radius FROM places',
          )
          .getSingle();
      expect(types.data.values, everyElement('real'));
      expect(
        () => placeFromRow(row.copyWith(latitude: 91)),
        throwsArgumentError,
      );
      expect(() => placeFromRow(row.copyWith(name: '')), throwsArgumentError);
      expect(() => placeFromRow(row.copyWith(kind: '0')), throwsArgumentError);
    });
  }

  test('course round trip includes independent nullable date bounds', () async {
    final date = LocalDate(2026, 2, 3);
    final courses = [
      sampleCourse(),
      sampleCourse().copyWith(id: 'from', activeFrom: () => date),
      sampleCourse().copyWith(id: 'until', activeUntil: () => date),
      sampleCourse().copyWith(
        id: 'both',
        activeFrom: () => date,
        activeUntil: () => LocalDate(2026, 11, 4),
      ),
    ];
    for (final course in courses) {
      await database.into(database.courses).insert(courseToCompanion(course));
      final row = await (database.select(
        database.courses,
      )..where((table) => table.id.equals(course.id))).getSingle();
      expect(courseFromRow(row), course);
      if (course.activeFrom != null) expect(row.activeFrom, '2026-02-03');
      expect(() => courseFromRow(row.copyWith(name: '')), throwsArgumentError);
      expect(
        () =>
            courseFromRow(row.copyWith(activeFrom: const Value('2026-02-30'))),
        throwsArgumentError,
      );
      expect(
        () => courseFromRow(row.copyWith(activeFrom: const Value('2026-2-03'))),
        throwsFormatException,
      );
    }
  });

  test('schedule slot round trip validates domain bounds on read', () async {
    await database
        .into(database.places)
        .insert(placeToCompanion(samplePlace()));
    await database
        .into(database.courses)
        .insert(courseToCompanion(sampleCourse()));
    final slot = sampleSlot().copyWith(
      weekday: 7,
      startMinute: 1439,
      durationMinutes: 120,
    );
    await database
        .into(database.scheduleSlots)
        .insert(scheduleSlotToCompanion(slot));
    final row = await database.select(database.scheduleSlots).getSingle();
    expect(scheduleSlotFromRow(row), slot);
    expect(
      () => scheduleSlotFromRow(row.copyWith(weekday: 0)),
      throwsRangeError,
    );
    expect(
      () => scheduleSlotFromRow(row.copyWith(durationMinutes: 0)),
      throwsArgumentError,
    );
  });

  for (final type in LocationEventType.values) {
    test(
      'event round trip stores ${type.name} with UTC milliseconds',
      () async {
        final instant = DateTime(2026, 10, 5, 9, 0, 0, 123);
        final event = sampleEvent().copyWith(type: type, recordedAt: instant);
        await database
            .into(database.locationEvents)
            .insert(locationEventToCompanion(event));
        final row = await database.select(database.locationEvents).getSingle();
        final mapped = locationEventFromRow(row);
        expect(mapped, event);
        expect(mapped.recordedAt.isUtc, isTrue);
        expect(row.recordedAt, instant.toUtc().millisecondsSinceEpoch);
        expect(row.type, type.name);
        expect(
          () => locationEventFromRow(
            row.copyWith(accuracyMeters: const Value(-1)),
          ),
          throwsArgumentError,
        );
        expect(
          () =>
              locationEventFromRow(row.copyWith(longitude: const Value(null))),
          throwsFormatException,
        );
      },
    );
  }

  test(
    'event nullable fields and negative epoch milliseconds round trip',
    () async {
      final events = [
        sampleEvent().copyWith(
          id: 'geofence',
          position: () => null,
          accuracyMeters: () => null,
          recordedAt: DateTime.fromMillisecondsSinceEpoch(-123, isUtc: true),
        ),
        sampleEvent().copyWith(
          id: 'sample',
          type: LocationEventType.positionSample,
          placeId: () => null,
          accuracyMeters: () => null,
        ),
      ];
      for (final event in events) {
        await database
            .into(database.locationEvents)
            .insert(locationEventToCompanion(event));
        final row = await (database.select(
          database.locationEvents,
        )..where((table) => table.id.equals(event.id))).getSingle();
        expect(locationEventFromRow(row), event);
      }
    },
  );

  for (final status in AttendanceStatus.values) {
    for (final source in AttendanceSource.values) {
      test(
        'attendance round trip stores ${status.name}/${source.name}',
        () async {
          final record = sampleAttendance().copyWith(
            status: status,
            source: source,
            checkInAt: () => DateTime(2026, 10, 5, 9, 0, 0, 321),
            evaluatedAt: DateTime(2026, 10, 5, 11, 0, 0, 987),
          );
          await database
              .into(database.attendanceRecords)
              .insert(attendanceRecordToCompanion(record));
          final row = await database
              .select(database.attendanceRecords)
              .getSingle();
          final mapped = attendanceRecordFromRow(row);
          expect(mapped, record);
          expect(mapped.evaluatedAt.isUtc, isTrue);
          expect(mapped.checkInAt!.isUtc, isTrue);
          expect(row.evaluatedAt, record.evaluatedAt.millisecondsSinceEpoch);
          expect(row.checkInAt, record.checkInAt!.millisecondsSinceEpoch);
          expect(row.occurrenceDate, '2026-10-05');
          expect(row.status, status.name);
          expect(row.source, source.name);
          expect(
            () => attendanceRecordFromRow(
              row.copyWith(checkInAt: Value(row.evaluatedAt + 1)),
            ),
            throwsArgumentError,
          );
        },
      );
    }
  }

  test('attendance null check-in round trip', () async {
    final record = sampleAttendance().copyWith(checkInAt: () => null);
    await database
        .into(database.attendanceRecords)
        .insert(attendanceRecordToCompanion(record));
    expect(
      attendanceRecordFromRow(
        await database.select(database.attendanceRecords).getSingle(),
      ),
      record,
    );
  });

  for (final mode in [...TravelMode.values, null]) {
    test('trip round trip stores ${mode?.name} with milliseconds', () async {
      final trip = sampleTrip().copyWith(
        mode: () => mode,
        departedAt: DateTime(2026, 10, 5, 8, 0, 0, 123),
        arrivedAt: DateTime(2026, 10, 5, 8, 30, 0, 456),
      );
      await database.into(database.trips).insert(tripToCompanion(trip));
      final row = await database.select(database.trips).getSingle();
      final mapped = tripFromRow(row);
      expect(mapped, trip);
      expect(mapped.departedAt.isUtc, isTrue);
      expect(mapped.arrivedAt.isUtc, isTrue);
      expect(row.departedAt, trip.departedAt.millisecondsSinceEpoch);
      expect(row.arrivedAt, trip.arrivedAt.millisecondsSinceEpoch);
      expect(row.mode, mode?.name);
      expect(
        () => tripFromRow(row.copyWith(arrivedAt: row.departedAt)),
        throwsArgumentError,
      );
    });
  }

  for (final mode in TravelMode.values) {
    test('settings round trip stores every field and ${mode.name}', () async {
      final settings = UserSettings(
        defaultTravelMode: mode,
        departureBufferMinutes: 8,
        attendancePolicy: AttendancePolicy(
          earlyWindowMinutes: 25,
          graceMinutes: 12,
          lateUntilMinutes: 45,
          maxAccuracyMeters: 123.456,
        ),
        notificationsEnabled: false,
      );
      await database
          .into(database.userSettingsTable)
          .insert(settingsToCompanion(settings));
      final row = await database.select(database.userSettingsTable).getSingle();
      expect(settingsFromRow(row), settings);
      expect(row.id, 1);
      expect(row.defaultTravelMode, mode.name);
      expect(
        () => settingsFromRow(row.copyWith(departureBufferMinutes: -1)),
        throwsArgumentError,
      );
      expect(
        () => settingsFromRow(row.copyWith(lateUntilMinutes: const Value(0))),
        throwsArgumentError,
      );
      expect(
        () => settingsFromRow(row.copyWith(maxAccuracyMeters: 0)),
        throwsArgumentError,
      );
    });
  }

  test('default settings including nullable policy round trip', () async {
    final settings = UserSettings();
    await database
        .into(database.userSettingsTable)
        .insert(settingsToCompanion(settings));
    expect(
      settingsFromRow(
        await database.select(database.userSettingsTable).getSingle(),
      ),
      settings,
    );
  });

  test(
    'local date codec preserves calendar boundaries and rejects malformed data',
    () {
      for (final date in [
        LocalDate(1, 1, 1),
        LocalDate(2024, 2, 29),
        LocalDate(9999, 12, 31),
      ]) {
        expect(localDateFromText(localDateToText(date)), date);
      }
      expect(localDateToText(LocalDate(1, 1, 1)), '0001-01-01');
      expect(() => localDateFromText('2026-10-05Z'), throwsFormatException);
      expect(() => localDateFromText('2026-13-01'), throwsArgumentError);
    },
  );
}
