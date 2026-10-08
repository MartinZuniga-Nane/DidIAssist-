import 'dart:io';

import 'package:did_i_attend/src/data/database/app_database.dart';
import 'package:did_i_attend/src/data/repositories/drift_attendance_repository.dart';
import 'package:did_i_attend/src/data/repositories/drift_settings_repository.dart';
import 'package:did_i_attend/src/domain/models/models.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/fixtures.dart';

void main() {
  test(
    'concurrent clients share a file database server and retain manual writes',
    () async {
      final buildDirectory = await Directory(
        'build',
      ).absolute.create(recursive: true);
      final scratch = await buildDirectory.createTemp('shared_database_');
      final databasePath =
          '${scratch.path}${Platform.pathSeparator}shared.sqlite';
      final name = 'test-${const Uuid().v4()}';
      final first = _client(name, databasePath, scratch.path);
      final second = _client(name, databasePath, scratch.path);
      addTearDown(() async {
        await Future.wait([first.close(), second.close()]);
        expect(
          scratch.absolute.path.startsWith(
            '${buildDirectory.path}${Platform.pathSeparator}',
          ),
          isTrue,
        );
        await _deleteAfterShutdown(scratch);
      });
      await Future.wait([
        first.customSelect('SELECT 1').get(),
        second.customSelect('SELECT 1').get(),
      ]);
      final settings = UserSettings(defaultTravelMode: TravelMode.transit);
      await DriftSettingsRepository(first).save(settings);
      expect(await DriftSettingsRepository(second).load(), settings);
      final automatic = sampleAttendance();
      final manual = automatic.copyWith(
        id: 'manual',
        source: AttendanceSource.manual,
        status: AttendanceStatus.excused,
      );
      final results = await Future.wait([
        DriftAttendanceRepository(first).upsert(automatic),
        DriftAttendanceRepository(second).upsert(manual),
      ]);
      final stored = await DriftAttendanceRepository(
        first,
      ).findBySlotAndDate(automatic.slotId, automatic.occurrenceDate);
      expect(stored, manual.copyWith(id: results.first.id));
      expect(results.map((record) => record.id).toSet(), hasLength(1));
      expect(await first.select(first.attendanceRecords).get(), hasLength(1));
    },
  );
}

// Keep isolate-bound path closures outside test state containing live clients.
AppDatabase _client(String name, String path, String temporaryPath) =>
    AppDatabase.forTesting(
      driftDatabase(
        name: name,
        native: DriftNativeOptions(
          shareAcrossIsolates: true,
          databasePath: () async => path,
          tempDirectoryPath: () async => temporaryPath,
        ),
      ),
    );

Future<void> _deleteAfterShutdown(Directory directory) async {
  // Shared server shutdown completes asynchronously after the last disconnect.
  for (var attempt = 0; ; attempt++) {
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException catch (error) {
      if (!Platform.isWindows ||
          error.osError?.errorCode != 32 ||
          attempt >= 49) {
        rethrow;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
}
