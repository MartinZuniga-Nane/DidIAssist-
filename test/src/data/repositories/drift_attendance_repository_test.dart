import 'dart:async';

import 'package:did_i_assist/src/core/local_date.dart';
import 'package:did_i_assist/src/data/database/app_database.dart';
import 'package:did_i_assist/src/data/repositories/drift_attendance_repository.dart';
import 'package:did_i_assist/src/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../domain/models/fixtures.dart';
import '../database/test_database.dart';

void main() {
  late AppDatabase database;
  late DriftAttendanceRepository repository;
  final date = LocalDate(2026, 10, 5);

  setUp(() {
    database = createTestDatabase();
    repository = DriftAttendanceRepository(database);
  });
  tearDown(() => database.close());

  test('empty reads and missing keys', () async {
    expect(await repository.findBySlotAndDate(slotId, date), isNull);
    expect(await repository.query(from: date, until: date.addDays(1)), isEmpty);
  });

  test('upsert inserts and retains ID on automatic updates', () async {
    final original = sampleAttendance();
    expect(await repository.upsert(original), original);
    final update = original.copyWith(
      id: 'new-id',
      status: AttendanceStatus.late,
      checkInAt: () => null,
    );
    expect(await repository.upsert(update), update.copyWith(id: original.id));
    expect(
      await repository.findBySlotAndDate(slotId, date),
      update.copyWith(id: original.id),
    );
    expect(await repository.findBySlotAndDate('other', date), isNull);
    expect(await repository.findBySlotAndDate(slotId, date.addDays(1)), isNull);
    expect(
      await database.select(database.attendanceRecords).get(),
      hasLength(1),
    );
  });

  test(
    'manual writes overwrite either source; automatic retains manual',
    () async {
      final original = sampleAttendance();
      await repository.upsert(original);
      final manual = original.copyWith(
        id: 'manual-id',
        source: AttendanceSource.manual,
        status: AttendanceStatus.excused,
      );
      final stored = manual.copyWith(id: original.id);
      expect(await repository.upsert(manual), stored);
      expect(
        await repository.upsert(original.copyWith(id: 'automatic-id')),
        stored,
      );
      final nextManual = manual.copyWith(
        id: 'next-manual',
        status: AttendanceStatus.absent,
        checkInAt: () => null,
      );
      expect(
        await repository.upsert(nextManual),
        nextManual.copyWith(id: original.id),
      );
    },
  );

  for (final manualFirst in [true, false]) {
    test(
      'parallel upserts protect manual and keep ID '
      '(manualFirst=$manualFirst)',
      () async {
        final automatic = sampleAttendance().copyWith(id: 'auto');
        final manual = automatic.copyWith(
          id: 'manual',
          source: AttendanceSource.manual,
          status: AttendanceStatus.excused,
        );
        final records = manualFirst ? [manual, automatic] : [automatic, manual];
        final results = await Future.wait(records.map(repository.upsert));
        final stored = await repository.findBySlotAndDate(slotId, date);
        expect(stored, manual.copyWith(id: results.first.id));
        expect(results.map((record) => record.id).toSet(), hasLength(1));
        expect(
          await database.select(database.attendanceRecords).get(),
          hasLength(1),
        );
      },
    );
  }

  test(
    'parallel automatic updates retain one row and the first stored ID',
    () async {
      final first = sampleAttendance().copyWith(id: 'first');
      final second = first.copyWith(
        id: 'second',
        status: AttendanceStatus.late,
      );
      final results = await Future.wait([
        repository.upsert(first),
        DriftAttendanceRepository(database).upsert(second),
      ]);
      expect(results.map((record) => record.id).toSet(), hasLength(1));
      expect(
        await repository.findBySlotAndDate(slotId, date),
        second.copyWith(id: results.first.id),
      );
      expect(
        await database.select(database.attendanceRecords).get(),
        hasLength(1),
      );
    },
  );

  test(
    'failed ID collision rolls back and does not change existing evidence',
    () async {
      final original = sampleAttendance();
      await repository.upsert(original);
      await expectLater(
        repository.upsert(original.copyWith(slotId: 'different')),
        throwsA(isA<Exception>()),
      );
      expect(await repository.findBySlotAndDate(slotId, date), original);
      expect(await repository.findBySlotAndDate('different', date), isNull);
    },
  );

  test('query is half-open, ordered by date and filters courses', () async {
    final original = sampleAttendance();
    final records = [
      original.copyWith(id: 'until', occurrenceDate: date.addDays(2)),
      original.copyWith(id: 'middle', occurrenceDate: date.addDays(1)),
      original.copyWith(id: 'before', occurrenceDate: date.addDays(-1)),
      original.copyWith(id: 'b', slotId: 'b', courseId: 'other'),
      original.copyWith(id: 'a', slotId: 'a'),
    ];
    for (final record in records) {
      await repository.upsert(record);
    }
    expect(
      (await repository.query(
        from: date,
        until: date.addDays(2),
      )).map((record) => record.id),
      ['a', 'b', 'middle'],
    );
    expect(
      (await repository.query(
        from: date,
        until: date.addDays(2),
        courseId: courseId,
      )).map((record) => record.id),
      ['a', 'middle'],
    );
    expect(await repository.query(from: date, until: date), isEmpty);
    expect(await repository.query(from: date.addDays(1), until: date), isEmpty);
    expect(
      await repository.query(
        from: date,
        until: date.addDays(2),
        courseId: 'missing',
      ),
      isEmpty,
    );
  });

  test(
    'upsert returns the persisted UTC value with millisecond precision',
    () async {
      final original = sampleAttendance().copyWith(
        checkInAt: () => DateTime(2026, 10, 5, 9, 0, 0, 123),
        evaluatedAt: DateTime(2026, 10, 5, 11, 0, 0, 987),
      );
      final stored = await repository.upsert(original);
      expect(stored, original);
      expect(stored.evaluatedAt.isUtc, isTrue);
      expect(stored.checkInAt!.isUtc, isTrue);
    },
  );

  test(
    'watch uses the same half-open range, filter and order as query',
    () async {
      final records = [
        sampleAttendance().copyWith(
          id: 'before',
          occurrenceDate: date.addDays(-1),
        ),
        sampleAttendance().copyWith(
          id: 'until',
          occurrenceDate: date.addDays(2),
        ),
        sampleAttendance().copyWith(
          id: 'other',
          slotId: 'other',
          courseId: 'other',
        ),
        sampleAttendance().copyWith(
          id: 'second',
          occurrenceDate: date.addDays(1),
        ),
        sampleAttendance().copyWith(id: 'first'),
      ];
      for (final record in records) {
        await repository.upsert(record);
      }
      final result = await repository
          .watch(from: date, until: date.addDays(2), courseId: courseId)
          .first;
      expect(result.map((record) => record.id), ['first', 'second']);
      expect(
        result,
        await repository.query(
          from: date,
          until: date.addDays(2),
          courseId: courseId,
        ),
      );
    },
  );

  test(
    'watch emits initially and after insert and protected manual updates',
    () async {
      final iterator = StreamIterator<List<AttendanceRecord>>(
        repository.watch(from: date, until: date.addDays(1)),
      );
      addTearDown(iterator.cancel);
      expect(
        await iterator.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
      expect(iterator.current, isEmpty);
      await repository.upsert(sampleAttendance());
      expect(
        await iterator.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
      expect(iterator.current, [sampleAttendance()]);
      final manual = sampleAttendance().copyWith(
        source: AttendanceSource.manual,
        status: AttendanceStatus.excused,
      );
      await repository.upsert(manual);
      expect(
        await iterator.moveNext().timeout(const Duration(seconds: 5)),
        isTrue,
      );
      expect(iterator.current, [manual]);
      expect(await repository.upsert(sampleAttendance()), manual);
      expect(await repository.query(from: date, until: date.addDays(1)), [
        manual,
      ]);
    },
  );
}
