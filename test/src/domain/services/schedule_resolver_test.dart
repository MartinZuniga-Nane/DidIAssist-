import 'package:did_i_assist/src/core/local_date.dart';
import 'package:did_i_assist/src/domain/models/models.dart';
import 'package:did_i_assist/src/domain/services/schedule_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

import '../models/fixtures.dart' as fixtures;

void main() {
  const resolver = ScheduleResolver();
  final course = fixtures.sampleCourse();
  final place = fixtures.samplePlace();
  final slot = fixtures.sampleSlot();

  List<ClassOccurrence> resolve({
    required DateTime from,
    required DateTime until,
    List<Course>? courses,
    List<ScheduleSlot>? slots,
    List<Place>? places,
  }) => resolver.occurrencesBetween(
    from: from,
    until: until,
    courses: courses ?? [course],
    slots: slots ?? [slot],
    places: places ?? [place],
  );

  group('occurrencesBetween', () {
    for (var weekday = 1; weekday <= 7; weekday++) {
      test('maps ISO weekday $weekday to the correct local date', () {
        final occurrences = resolve(
          from: DateTime(2026, 10, 5),
          until: DateTime(2026, 10, 12),
          slots: [slot.copyWith(weekday: weekday)],
        );
        expect(occurrences, hasLength(1));
        expect(occurrences.single.start, DateTime(2026, 10, 4 + weekday, 9));
        expect(occurrences.single.end, DateTime(2026, 10, 4 + weekday, 10, 30));
      });
    }

    final boundaries = [
      (
        name: 'includes the lower bound',
        from: DateTime(2026, 10, 5, 9),
        until: DateTime(2026, 10, 5, 10),
        count: 1,
      ),
      (
        name: 'excludes the upper bound',
        from: DateTime(2026, 10, 5, 8),
        until: DateTime(2026, 10, 5, 9),
        count: 0,
      ),
      (
        name: 'excludes a start one microsecond before the lower bound',
        from: DateTime(2026, 10, 5, 9, 0, 0, 0, 1),
        until: DateTime(2026, 10, 6),
        count: 0,
      ),
      (
        name: 'includes a start one microsecond before the upper bound',
        from: DateTime(2026, 10, 5, 8),
        until: DateTime(2026, 10, 5, 9, 0, 0, 0, 1),
        count: 1,
      ),
      (
        name: 'returns no occurrences for an empty range',
        from: DateTime(2026, 10, 5, 9),
        until: DateTime(2026, 10, 5, 9),
        count: 0,
      ),
      (
        name: 'excludes ongoing classes starting outside the range',
        from: DateTime(2026, 10, 5, 9, 30),
        until: DateTime(2026, 10, 5, 10),
        count: 0,
      ),
    ];
    for (final boundary in boundaries) {
      test(boundary.name, () {
        expect(
          resolve(from: boundary.from, until: boundary.until),
          hasLength(boundary.count),
        );
      });
    }

    test('rejects reversed ranges', () {
      expect(
        () =>
            resolve(from: DateTime(2026, 10, 6), until: DateTime(2026, 10, 5)),
        throwsArgumentError,
      );
    });

    test('semester bounds include the first and last active dates', () {
      final bounded = course.copyWith(
        activeFrom: () => LocalDate(2026, 10, 5),
        activeUntil: () => LocalDate(2026, 10, 12),
      );
      final occurrences = resolve(
        from: DateTime(2026, 9, 28),
        until: DateTime(2026, 10, 20),
        courses: [bounded],
      );
      expect(occurrences.map((value) => value.occurrenceDate), [
        LocalDate(2026, 10, 5),
        LocalDate(2026, 10, 12),
      ]);
    });

    test('supports one-sided semester bounds', () {
      expect(
        resolve(
          from: DateTime(2026, 10, 5),
          until: DateTime(2026, 10, 20),
          courses: [course.copyWith(activeFrom: () => LocalDate(2026, 10, 12))],
        ).map((value) => value.occurrenceDate),
        [LocalDate(2026, 10, 12), LocalDate(2026, 10, 19)],
      );
      expect(
        resolve(
          from: DateTime(2026, 10, 5),
          until: DateTime(2026, 10, 20),
          courses: [
            course.copyWith(activeUntil: () => LocalDate(2026, 10, 12)),
          ],
        ).map((value) => value.occurrenceDate),
        [LocalDate(2026, 10, 5), LocalDate(2026, 10, 12)],
      );
    });

    test('orders by start then slot ID regardless of input order', () {
      final first = slot.copyWith(id: fixtures.courseId);
      final second = slot.copyWith(id: fixtures.recordId);
      final earlier = slot.copyWith(id: fixtures.homeId, startMinute: 480);
      final input = [second, first, earlier];
      final occurrences = resolve(
        from: DateTime(2026, 10, 5),
        until: DateTime(2026, 10, 13),
        slots: input,
      );
      expect(occurrences.map((value) => value.slot.id), [
        earlier.id,
        first.id,
        second.id,
        earlier.id,
        first.id,
        second.id,
      ]);
      expect(input, [second, first, earlier]);
    });

    for (final missing in ['course', 'place']) {
      test('skips slots whose $missing is missing', () {
        expect(
          resolve(
            from: DateTime(2026, 10, 5),
            until: DateTime(2026, 10, 13),
            courses: missing == 'course' ? [] : [course],
            places: missing == 'place' ? [] : [place],
          ),
          isEmpty,
        );
      });
    }

    test(
      'constructs overnight endpoints and keeps the starting local date',
      () {
        final occurrence = resolve(
          from: DateTime(2026, 10, 5, 23),
          until: DateTime(2026, 10, 6),
          slots: [slot.copyWith(startMinute: 1410)],
        ).single;
        expect(occurrence.start, DateTime(2026, 10, 5, 23, 30));
        expect(occurrence.end, DateTime(2026, 10, 6, 1));
        expect(occurrence.occurrenceDate, LocalDate(2026, 10, 5));
      },
    );

    test('accepts UTC range bounds while constructing local occurrences', () {
      final from = DateTime(2026, 10, 5, 8).toUtc();
      final until = DateTime(2026, 10, 5, 10).toUtc();
      final occurrence = resolve(from: from, until: until).single;
      expect(occurrence.start, DateTime(2026, 10, 5, 9));
      expect(occurrence.start.isUtc, isFalse);
    });

    test('keeps noon wall-clock time across DST transition weekends', () {
      final dailySlots = [
        for (var weekday = 1; weekday <= 7; weekday++)
          slot.copyWith(
            weekday: weekday,
            startMinute: 720,
            id:
                '00000000-0000-4000-8000-'
                '${weekday.toString().padLeft(12, '0')}',
          ),
      ];
      for (final range in [
        (
          from: DateTime(2026, 4, 3),
          until: DateTime(2026, 4, 7),
          expected: [
            DateTime(2026, 4, 3, 12),
            DateTime(2026, 4, 4, 12),
            DateTime(2026, 4, 5, 12),
            DateTime(2026, 4, 6, 12),
          ],
        ),
        (
          from: DateTime(2026, 9, 4),
          until: DateTime(2026, 9, 8),
          expected: [
            DateTime(2026, 9, 4, 12),
            DateTime(2026, 9, 5, 12),
            DateTime(2026, 9, 6, 12),
            DateTime(2026, 9, 7, 12),
          ],
        ),
      ]) {
        expect(
          resolve(
            from: range.from,
            until: range.until,
            slots: dailySlots,
          ).map((value) => value.start),
          range.expected,
        );
      }
    });
  });

  group('nextOccurrence', () {
    ClassOccurrence? next(
      DateTime after, {
      List<Course>? courses,
      List<ScheduleSlot>? slots,
      List<Place>? places,
    }) => resolver.nextOccurrence(
      after: after,
      courses: courses ?? [course],
      slots: slots ?? [slot],
      places: places ?? [place],
    );

    test('finds a later class today but excludes an exact start', () {
      expect(next(DateTime(2026, 10, 5, 8))!.start, DateTime(2026, 10, 5, 9));
      expect(next(DateTime(2026, 10, 5, 9))!.start, DateTime(2026, 10, 12, 9));
    });

    test(
      'jumps to a distant semester instead of using a fixed search horizon',
      () {
        final future = course.copyWith(
          activeFrom: () => LocalDate(2030, 1, 1),
          activeUntil: () => LocalDate(2030, 1, 7),
        );
        expect(
          next(DateTime(2026, 10, 5), courses: [future])!.start,
          DateTime(2030, 1, 7, 9),
        );
      },
    );

    test('orders simultaneous candidates by slot ID', () {
      expect(
        next(
          DateTime(2026, 10, 5, 8),
          slots: [
            slot.copyWith(id: fixtures.recordId),
            slot.copyWith(id: fixtures.courseId),
          ],
        )!.slot.id,
        fixtures.courseId,
      );
    });

    test('returns null for expired semesters and missing references', () {
      expect(
        next(
          DateTime(2026, 10, 5),
          courses: [
            course.copyWith(activeUntil: () => LocalDate(2026, 10, 4)),
          ],
        ),
        isNull,
      );
      expect(next(DateTime(2026, 10, 5), courses: []), isNull);
      expect(next(DateTime(2026, 10, 5), places: []), isNull);
      expect(next(DateTime(2026, 10, 5), slots: []), isNull);
    });
  });

  group('occurrenceAt', () {
    ClassOccurrence? at(DateTime instant, {List<ScheduleSlot>? slots}) =>
        resolver.occurrenceAt(
          instant: instant,
          courses: [course],
          slots: slots ?? [slot],
          places: [place],
        );

    test('includes start and excludes end', () {
      expect(at(DateTime(2026, 10, 5, 9))!.slot, slot);
      expect(at(DateTime(2026, 10, 5, 10, 29, 59))!.slot, slot);
      expect(at(DateTime(2026, 10, 5, 8, 59, 59)), isNull);
      expect(at(DateTime(2026, 10, 5, 10, 30)), isNull);
    });

    test('finds an overnight class on the following calendar day', () {
      final overnight = slot.copyWith(startMinute: 1410);
      expect(
        at(DateTime(2026, 10, 6, 0, 30), slots: [overnight])!.occurrenceDate,
        LocalDate(2026, 10, 5),
      );
      expect(at(DateTime(2026, 10, 6, 1), slots: [overnight]), isNull);
    });

    test('supports durations longer than a single calendar day', () {
      final longSlot = slot.copyWith(durationMinutes: 2880);
      expect(at(DateTime(2026, 10, 7, 8), slots: [longSlot])!.slot, longSlot);
      expect(at(DateTime(2026, 10, 7, 9), slots: [longSlot]), isNull);
    });

    test('chooses the earliest start then slot ID for overlapping classes', () {
      final simultaneous = slot.copyWith(id: fixtures.courseId);
      final later = slot.copyWith(id: fixtures.recordId, startMinute: 570);
      expect(
        at(DateTime(2026, 10, 5, 10), slots: [later, slot, simultaneous])!.slot,
        simultaneous,
      );
    });

    test('returns null when no slots exist', () {
      expect(at(DateTime(2026, 10, 5, 9), slots: []), isNull);
    });
  });
}
