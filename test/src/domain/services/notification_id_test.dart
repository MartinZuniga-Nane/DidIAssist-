import 'package:did_i_assist/src/core/local_date.dart';
import 'package:did_i_assist/src/domain/models/planned_notification.dart';
import 'package:did_i_assist/src/domain/services/notification_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final date = LocalDate(2026, 10, 5);
  for (final entry in [
    (NotificationKind.departureReminder, 'slot', 689725607),
    (NotificationKind.departureReminder, 'slot-2', 511522656),
    (NotificationKind.attendanceResult, 'slot', 1746694229),
    (NotificationKind.attendanceResult, 'slot-2', 1561165014),
  ]) {
    test('stable FNV-1a value for ${entry.$1.name} / ${entry.$2}', () {
      for (var attempt = 0; attempt < 3; attempt++) {
        expect(
          notificationId(
            kind: entry.$1,
            slotId: entry.$2,
            occurrenceDate: date,
          ),
          entry.$3,
        );
      }
    });
  }

  test('10,000 identities have no collisions and fit signed 31-bit IDs', () {
    final ids = <int>{};
    for (final kind in NotificationKind.values) {
      for (var slot = 0; slot < 100; slot++) {
        for (var day = 0; day < 50; day++) {
          final id = notificationId(
            kind: kind,
            slotId: 'slot-$slot',
            occurrenceDate: date.addDays(day),
          );
          expect(id, inInclusiveRange(0, 0x7fffffff));
          expect(ids.add(id), isTrue);
          expect(id >> 30, kind.index);
        }
      }
    }
  });

  test('UTF-8 identifiers and dates affect the identity', () {
    final first = notificationId(
      kind: NotificationKind.departureReminder,
      slotId: 'matemáticas:1',
      occurrenceDate: date,
    );
    expect(
      first,
      isNot(
        notificationId(
          kind: NotificationKind.departureReminder,
          slotId: 'matematicas:1',
          occurrenceDate: date,
        ),
      ),
    );
    expect(
      first,
      isNot(
        notificationId(
          kind: NotificationKind.departureReminder,
          slotId: 'matemáticas:1',
          occurrenceDate: date.addDays(1),
        ),
      ),
    );
    expect(
      () => notificationId(
        kind: NotificationKind.departureReminder,
        slotId: ' ',
        occurrenceDate: date,
      ),
      throwsArgumentError,
    );
  });
}
