import 'package:did_i_assist/src/domain/location/position_fix.dart';
import 'package:flutter_test/flutter_test.dart';

import '../services/fixtures.dart';

void main() {
  final time = DateTime(2026, 10, 5, 9);
  PositionFix fix() => PositionFix(
    position: eiffelTower(),
    timestamp: time,
    accuracyMeters: 20,
  );

  test('normalizes timestamp to UTC and has value equality', () {
    expect(fix().timestamp.isUtc, isTrue);
    expect(fix().timestamp, time.toUtc());
    expect(fix(), fix());
    expect(fix().hashCode, fix().hashCode);
  });

  test('copyWith preserves, replaces and clears nullable accuracy', () {
    final original = fix();
    expect(original.copyWith(), original);
    expect(original.copyWith(position: louvre()), isNot(original));
    expect(
      original.copyWith(timestamp: time.add(const Duration(seconds: 1))),
      isNot(original),
    );
    expect(original.copyWith(accuracyMeters: () => 0), isNot(original));
    expect(
      original.copyWith(accuracyMeters: () => null).accuracyMeters,
      isNull,
    );
  });

  test(
    'unknown and zero accuracy are allowed; invalid accuracy is rejected',
    () {
      expect(fix().copyWith(accuracyMeters: () => null).accuracyMeters, isNull);
      expect(fix().copyWith(accuracyMeters: () => 0).accuracyMeters, 0);
      for (final invalid in [-1.0, double.nan, double.infinity]) {
        expect(
          () => fix().copyWith(accuracyMeters: () => invalid),
          throwsArgumentError,
        );
      }
    },
  );
}
