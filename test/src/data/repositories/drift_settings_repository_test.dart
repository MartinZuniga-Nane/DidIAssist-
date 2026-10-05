import 'dart:async';

import 'package:did_i_assist/src/data/database/app_database.dart';
import 'package:did_i_assist/src/data/repositories/drift_settings_repository.dart';
import 'package:did_i_assist/src/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../database/test_database.dart';

void main() {
  late AppDatabase database;
  late DriftSettingsRepository repository;

  setUp(() {
    database = createTestDatabase();
    repository = DriftSettingsRepository(database);
  });
  tearDown(() => database.close());

  test(
    'empty settings return domain defaults without inserting a row',
    () async {
      expect(await repository.load(), UserSettings());
      expect(await repository.load(), UserSettings());
      expect(await database.select(database.userSettingsTable).get(), isEmpty);
    },
  );

  test(
    'save and load persist every setting and replace the singleton row',
    () async {
      final settings = UserSettings(
        defaultTravelMode: TravelMode.transit,
        departureBufferMinutes: 12,
        attendancePolicy: AttendancePolicy(
          earlyWindowMinutes: 25,
          graceMinutes: 12,
          lateUntilMinutes: 45,
          maxAccuracyMeters: 175.5,
        ),
        notificationsEnabled: false,
      );
      await repository.save(settings);
      expect(await repository.load(), settings);
      expect(await DriftSettingsRepository(database).load(), settings);
      final updated = settings.copyWith(
        defaultTravelMode: TravelMode.cycling,
        departureBufferMinutes: 0,
        attendancePolicy: AttendancePolicy(
          earlyWindowMinutes: 0,
          graceMinutes: 0,
          maxAccuracyMeters: 99.9,
        ),
        notificationsEnabled: true,
      );
      await repository.save(updated);
      expect(await repository.load(), updated);
      final rows = await database.select(database.userSettingsTable).get();
      expect(rows, hasLength(1));
      expect(rows.single.id, 1);
      expect(rows.single.lateUntilMinutes, isNull);
    },
  );

  test('default settings can be saved explicitly', () async {
    final defaults = UserSettings();
    await repository.save(defaults);
    expect(await repository.load(), defaults);
    expect(
      await database.select(database.userSettingsTable).get(),
      hasLength(1),
    );
  });

  test(
    'watch emits defaults and subsequent distinct settings changes',
    () async {
      final initial = Completer<void>();
      final updated = Completer<void>();
      final values = <UserSettings>[];
      final next = UserSettings(notificationsEnabled: false);
      final subscription = repository.watch().listen((value) {
        values.add(value);
        if (!initial.isCompleted) initial.complete();
        if (value == next && !updated.isCompleted) updated.complete();
      });
      addTearDown(subscription.cancel);
      await initial.future;
      await repository.save(UserSettings());
      await repository.load();
      await repository.save(next);
      await updated.future;
      expect(values, [UserSettings(), next]);
    },
  );

  test('parallel saves retain one complete settings value', () async {
    final first = UserSettings(defaultTravelMode: TravelMode.driving);
    final second = UserSettings(
      defaultTravelMode: TravelMode.cycling,
      notificationsEnabled: false,
    );
    await Future.wait([repository.save(first), repository.save(second)]);
    expect(await repository.load(), second);
    expect(
      await database.select(database.userSettingsTable).get(),
      hasLength(1),
    );
  });
}
