import 'package:did_i_assist/src/domain/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  test('normalizes timestamps and computes the duration', () {
    final departure = DateTime(2026, 10, 5, 8);
    final arrival = DateTime(2026, 10, 5, 8, 30);
    final trip = sampleTrip().copyWith(
      departedAt: departure,
      arrivedAt: arrival,
    );
    expect(trip.departedAt.isUtc, isTrue);
    expect(trip.arrivedAt.isUtc, isTrue);
    expect(trip.departedAt, departure.toUtc());
    expect(trip.arrivedAt, arrival.toUtc());
    expect(trip.duration, const Duration(minutes: 30));
  });

  test('has value equality and copyWith changes each field', () {
    final trip = sampleTrip();
    expectValueEquality(trip, sampleTrip(), [
      trip.copyWith(id: slotId),
      trip.copyWith(fromPlaceId: courseId),
      trip.copyWith(toPlaceId: courseId),
      trip.copyWith(departedAt: DateTime.utc(2026, 10, 5, 8, 5)),
      trip.copyWith(arrivedAt: DateTime.utc(2026, 10, 5, 8, 35)),
      trip.copyWith(mode: () => TravelMode.walking),
    ]);
    expect(trip.copyWith(), trip);
    expect(trip.copyWith(mode: () => null).mode, isNull);
  });

  test(
    'accepts an unknown mode and trips outside the learned commute range',
    () {
      final trip = Trip(
        id: recordId,
        fromPlaceId: homeId,
        toPlaceId: placeId,
        departedAt: DateTime.utc(2026, 10, 5),
        arrivedAt: DateTime.utc(2026, 10, 6),
      );
      expect(trip.mode, isNull);
      expect(trip.duration, const Duration(days: 1));
    },
  );

  test('rejects nonpositive durations, identical endpoints and blank IDs', () {
    final trip = sampleTrip();
    expect(
      () => trip.copyWith(arrivedAt: trip.departedAt),
      throwsArgumentError,
    );
    expect(
      () => trip.copyWith(
        arrivedAt: trip.departedAt.subtract(const Duration(seconds: 1)),
      ),
      throwsArgumentError,
    );
    expect(
      () => trip.copyWith(toPlaceId: trip.fromPlaceId),
      throwsArgumentError,
    );
    expect(() => trip.copyWith(id: ''), throwsArgumentError);
    expect(() => trip.copyWith(fromPlaceId: ''), throwsArgumentError);
    expect(() => trip.copyWith(toPlaceId: ''), throwsArgumentError);
  });
}
