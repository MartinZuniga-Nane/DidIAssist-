import 'package:did_i_assist/src/domain/models/planned_notification.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final at = DateTime(2026, 10, 5, 8);
  PlannedNotification make({
    int id = 1,
    NotificationKind kind = NotificationKind.departureReminder,
    Map<String, String> payload = const {'courseName': 'Mathematics'},
  }) => PlannedNotification(id: id, kind: kind, at: at, payload: payload);

  test('timestamps normalize to UTC and values compare deeply', () {
    expect(make().at.isUtc, isTrue);
    expect(make(), make());
    expect(make().hashCode, make().hashCode);
    expect(make(), isNot(make(id: 2)));
    expect(make(), isNot(make(kind: NotificationKind.attendanceResult)));
    expect(make(), isNot(make(payload: const {'courseName': 'Physics'})));
  });

  test('payload is a defensive immutable copy', () {
    final payload = {'courseName': 'Mathematics'};
    final value = make(payload: payload);
    payload['courseName'] = 'Physics';
    expect(value.payload['courseName'], 'Mathematics');
    expect(value.payload.clear, throwsUnsupportedError);
  });

  test('copyWith retains identity and replaces scheduling data', () {
    final original = make();
    expect(original.copyWith(), original);
    final updated = original.copyWith(
      at: at.add(const Duration(minutes: 5)),
      payload: const {'courseName': 'Physics'},
    );
    expect(updated.id, original.id);
    expect(updated.kind, original.kind);
    expect(updated.at, at.add(const Duration(minutes: 5)).toUtc());
    expect(updated.payload['courseName'], 'Physics');
  });

  for (final id in [-1, 0x80000000]) {
    test('rejects ID $id outside the signed 31-bit range', () {
      expect(() => make(id: id), throwsRangeError);
    });
  }

  test('accepts both ID boundaries and rejects blank payload keys', () {
    expect(make(id: 0).id, 0);
    expect(make(id: 0x7fffffff).id, 0x7fffffff);
    expect(() => make(payload: const {' ': 'value'}), throwsArgumentError);
  });
}
