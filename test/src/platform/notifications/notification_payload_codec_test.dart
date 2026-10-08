import 'dart:convert';

import 'package:did_i_attend/src/domain/models/planned_notification.dart';
import 'package:did_i_attend/src/platform/notifications/notification_payload_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const codec = NotificationPayloadCodec();
  final notification = PlannedNotification(
    id: 42,
    kind: NotificationKind.departureReminder,
    at: DateTime.utc(2026, 10, 5, 8),
    payload: const {'courseName': 'Matemáticas', 'etaMinutes': '20'},
  );

  test('persisted envelope reconstructs scheduling metadata after restart', () {
    final encoded = codec.encode(notification);
    expect(codec.decode(notification.id, encoded), notification);
    expect(codec.encode(codec.decode(notification.id, encoded)!), encoded);
  });

  for (final encoded in [
    null,
    '',
    'not-json',
    '{}',
    '[]',
    'null',
    '{"owner":"another-app"}',
  ]) {
    test('ignores unrelated or malformed payload $encoded', () {
      expect(codec.decode(42, encoded), isNull);
    });
  }

  test('ignores mismatched request IDs', () {
    expect(codec.decode(43, codec.encode(notification)), isNull);
  });

  for (final entry in [
    ('version', 2),
    ('kind', 'unknown'),
    ('at', 'invalid'),
    ('id', -1),
    ('payload', {'etaMinutes': 20}),
  ]) {
    test('ignores invalid envelope field ${entry.$1}', () {
      final envelope =
          jsonDecode(codec.encode(notification)) as Map<String, dynamic>;
      envelope[entry.$1] = entry.$2;
      expect(codec.decode(42, jsonEncode(envelope)), isNull);
    });
  }
}
