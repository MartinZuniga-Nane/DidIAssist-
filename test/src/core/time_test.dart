import 'package:clock/clock.dart';
import 'package:did_i_assist/src/core/local_date.dart';
import 'package:did_i_assist/src/core/time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses an injected clock and returns UTC', () {
    final instant = DateTime(2026, 10, 5, 9, 30);
    final fixed = Clock.fixed(instant);
    expect(utcNow(timeSource: fixed), instant.toUtc());
    expect(utcNow(timeSource: fixed).isUtc, isTrue);
    expect(today(timeSource: fixed), LocalDate(2026, 10, 5));
  });

  test('honors the scoped package clock', () {
    final instant = DateTime(2026, 12, 31, 23, 59);
    withClock(Clock.fixed(instant), () {
      expect(utcNow(), instant.toUtc());
      expect(today(), LocalDate(2026, 12, 31));
    });
  });
}
