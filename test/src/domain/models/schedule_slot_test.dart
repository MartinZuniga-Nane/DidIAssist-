import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  test('has value equality and copyWith changes each field', () {
    final slot = sampleSlot();
    expectValueEquality(slot, sampleSlot(), [
      slot.copyWith(id: recordId),
      slot.copyWith(courseId: recordId),
      slot.copyWith(placeId: homeId),
      slot.copyWith(weekday: DateTime.tuesday),
      slot.copyWith(startMinute: 600),
      slot.copyWith(durationMinutes: 120),
    ]);
    expect(slot.copyWith(), slot);
    expect(slot.copyWith(startMinute: 600).durationMinutes, 90);
  });

  test('accepts weekday and start minute boundaries', () {
    expect(sampleSlot().copyWith(weekday: 1, startMinute: 0).weekday, 1);
    expect(
      sampleSlot().copyWith(weekday: 7, startMinute: 1439).startMinute,
      1439,
    );
    expect(sampleSlot().copyWith(durationMinutes: 1).durationMinutes, 1);
  });

  test('rejects invalid weekdays, start minutes, durations and IDs', () {
    for (final day in [0, 8]) {
      expect(() => sampleSlot().copyWith(weekday: day), throwsRangeError);
    }
    for (final minute in [-1, 1440]) {
      expect(
        () => sampleSlot().copyWith(startMinute: minute),
        throwsRangeError,
      );
    }
    for (final duration in [0, -1]) {
      expect(
        () => sampleSlot().copyWith(durationMinutes: duration),
        throwsArgumentError,
      );
    }
    expect(() => sampleSlot().copyWith(id: ''), throwsArgumentError);
    expect(() => sampleSlot().copyWith(courseId: ''), throwsArgumentError);
    expect(() => sampleSlot().copyWith(placeId: ''), throwsArgumentError);
  });
}
