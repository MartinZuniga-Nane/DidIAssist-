import 'dart:convert';

import 'package:did_i_attend/src/domain/models/planned_notification.dart';

final class NotificationPayloadCodec {
  const NotificationPayloadCodec();

  String encode(PlannedNotification notification) => jsonEncode({
    'owner': 'did_i_attend.notifications',
    'version': 1,
    'id': notification.id,
    'kind': notification.kind.name,
    'at': notification.at.toIso8601String(),
    'payload': notification.payload,
  });

  PlannedNotification? decode(int requestId, String? encoded) {
    if (encoded == null) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded case {
        'owner': 'did_i_attend.notifications',
        'version': 1,
        'id': final int id,
        'kind': final String kind,
        'at': final String at,
        'payload': final Map<Object?, Object?> payload,
      }) {
        if (id != requestId ||
            id < 0 ||
            id > 0x7fffffff ||
            payload.entries.any(
              (entry) =>
                  entry.key is! String ||
                  (entry.key! as String).trim().isEmpty ||
                  entry.value is! String,
            )) {
          return null;
        }
        NotificationKind? parsedKind;
        for (final value in NotificationKind.values) {
          if (value.name == kind) parsedKind = value;
        }
        final instant = DateTime.tryParse(at);
        if (parsedKind == null || instant == null || !instant.isUtc) {
          return null;
        }
        return PlannedNotification(
          id: id,
          kind: parsedKind,
          at: instant,
          payload: payload.cast<String, String>(),
        );
      }
    } on FormatException {
      return null;
    }
    return null;
  }
}
