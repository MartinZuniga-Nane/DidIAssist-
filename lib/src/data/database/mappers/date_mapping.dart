import 'package:did_i_attend/src/core/local_date.dart';

String localDateToText(LocalDate date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

LocalDate localDateFromText(String text) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
    throw FormatException('Expected a local date in YYYY-MM-DD format.', text);
  }
  return LocalDate(
    int.parse(text.substring(0, 4)),
    int.parse(text.substring(5, 7)),
    int.parse(text.substring(8, 10)),
  );
}

DateTime instantFromMilliseconds(int milliseconds) =>
    DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);

int instantToMilliseconds(DateTime instant) =>
    instant.toUtc().millisecondsSinceEpoch;

// Both half-open bounds round up because persisted instants are whole
// milliseconds. Truncation would change inclusion at submillisecond bounds.
int instantCeilingMilliseconds(DateTime instant) {
  final microseconds = instant.toUtc().microsecondsSinceEpoch;
  final milliseconds = microseconds ~/ Duration.microsecondsPerMillisecond;
  return milliseconds +
      (microseconds > 0 &&
              microseconds % Duration.microsecondsPerMillisecond != 0
          ? 1
          : 0);
}
