import 'package:did_i_attend/src/domain/models/model_validation.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

enum NotificationKind { departureReminder, attendanceResult }

@immutable
final class PlannedNotification extends Equatable {
  PlannedNotification({
    required this.id,
    required this.kind,
    required DateTime at,
    Map<String, String> payload = const {},
  }) : at = at.toUtc(),
       payload = Map.unmodifiable(payload) {
    if (id < 0 || id > 0x7fffffff) {
      throw RangeError.range(id, 0, 0x7fffffff, 'id');
    }
    for (final key in payload.keys) {
      requireNonBlank(key, 'payload key');
    }
  }

  final int id;
  final NotificationKind kind;
  final DateTime at;
  final Map<String, String> payload;

  PlannedNotification copyWith({
    DateTime? at,
    Map<String, String>? payload,
  }) => PlannedNotification(
    id: id,
    kind: kind,
    at: at ?? this.at,
    payload: payload ?? this.payload,
  );

  @override
  List<Object> get props => [id, kind, at, payload];
}
