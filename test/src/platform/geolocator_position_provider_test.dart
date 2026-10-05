import 'dart:async';

import 'package:did_i_assist/src/domain/location/position_provider.dart';
import 'package:did_i_assist/src/platform/geolocator_position_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mocktail/mocktail.dart';

import '../domain/services/fixtures.dart';

final class MockGeolocatorPlatform extends Mock
    implements geo.GeolocatorPlatform {}

void main() {
  final timestamp = DateTime(2026, 10, 5, 9);
  geo.Position position({double accuracy = 20}) => geo.Position(
    longitude: 2.2945,
    latitude: 48.8584,
    timestamp: timestamp,
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
  late MockGeolocatorPlatform platform;
  late GeolocatorPositionProvider provider;

  setUpAll(() => registerFallbackValue(const geo.LocationSettings()));
  setUp(() {
    platform = MockGeolocatorPlatform();
    when(
      () => platform.isLocationServiceEnabled(),
    ).thenAnswer((_) async => true);
    when(
      () => platform.checkPermission(),
    ).thenAnswer((_) async => geo.LocationPermission.whileInUse);
    when(
      () => platform.getCurrentPosition(
        locationSettings: any(named: 'locationSettings'),
      ),
    ).thenAnswer((_) async => position());
    when(
      () => platform.getLastKnownPosition(),
    ).thenAnswer((_) async => position());
    provider = GeolocatorPositionProvider(platform: platform);
  });

  test(
    'maps current coordinates, accuracy and UTC timestamp with a timeout',
    () async {
      final fix = await provider.currentFix(
        timeout: const Duration(seconds: 5),
      );
      expect(fix.position, eiffelTower());
      expect(fix.accuracyMeters, 20);
      expect(fix.timestamp, timestamp.toUtc());
      expect(fix.timestamp.isUtc, isTrue);
      final settings =
          verify(
                () => platform.getCurrentPosition(
                  locationSettings: captureAny(named: 'locationSettings'),
                ),
              ).captured.single
              as geo.LocationSettings;
      expect(settings.accuracy, geo.LocationAccuracy.high);
      expect(settings.timeLimit, const Duration(seconds: 5));
      verifyNever(() => platform.requestPermission());
    },
  );

  test('always permission also allows a current fix', () async {
    when(
      () => platform.checkPermission(),
    ).thenAnswer((_) async => geo.LocationPermission.always);
    expect((await provider.currentFix()).position, eiffelTower());
  });

  for (final permission in [
    geo.LocationPermission.denied,
    geo.LocationPermission.deniedForever,
    geo.LocationPermission.unableToDetermine,
  ]) {
    test(
      '$permission becomes a typed permission failure without a request',
      () async {
        when(
          () => platform.checkPermission(),
        ).thenAnswer((_) async => permission);
        await expectLater(
          provider.currentFix(),
          throwsA(
            isA<PositionUnavailable>().having(
              (failure) => failure.reason,
              'reason',
              PositionFailureReason.permissionDenied,
            ),
          ),
        );
        verifyNever(
          () => platform.getCurrentPosition(
            locationSettings: any(named: 'locationSettings'),
          ),
        );
        verifyNever(() => platform.requestPermission());
      },
    );
  }

  test(
    'disabled service is typed and never asks for a fix or permission',
    () async {
      when(
        () => platform.isLocationServiceEnabled(),
      ).thenAnswer((_) async => false);
      await expectLater(
        provider.currentFix(),
        throwsA(
          isA<PositionUnavailable>().having(
            (failure) => failure.reason,
            'reason',
            PositionFailureReason.serviceDisabled,
          ),
        ),
      );
      verifyNever(() => platform.checkPermission());
      verifyNever(
        () => platform.getCurrentPosition(
          locationSettings: any(named: 'locationSettings'),
        ),
      );
    },
  );

  final errors = [
    (TimeoutException('no fix'), PositionFailureReason.timeout),
    (
      const geo.PermissionDeniedException('denied'),
      PositionFailureReason.permissionDenied,
    ),
    (
      const geo.LocationServiceDisabledException(),
      PositionFailureReason.serviceDisabled,
    ),
  ];
  for (final (error, reason) in errors) {
    test(
      'translates plugin ${error.runtimeType} for current and cached fixes',
      () async {
        when(
          () => platform.getCurrentPosition(
            locationSettings: any(named: 'locationSettings'),
          ),
        ).thenThrow(error);
        when(() => platform.getLastKnownPosition()).thenThrow(error);
        final matcher = throwsA(
          isA<PositionUnavailable>().having(
            (failure) => failure.reason,
            'reason',
            reason,
          ),
        );
        await expectLater(provider.currentFix(), matcher);
        await expectLater(provider.lastKnownFix(), matcher);
      },
    );
  }

  test(
    'maps cached fix or null without requiring live location services',
    () async {
      final fix = await provider.lastKnownFix();
      expect(fix!.position, eiffelTower());
      expect(fix.timestamp, timestamp.toUtc());
      expect(fix.accuracyMeters, 20);
      when(() => platform.getLastKnownPosition()).thenAnswer((_) async => null);
      expect(await provider.lastKnownFix(), isNull);
      verifyNever(() => platform.isLocationServiceEnabled());
    },
  );

  test(
    'invalid native accuracy is mapped as unknown, including cached fixes',
    () async {
      for (final accuracy in [-1.0, double.nan, double.infinity]) {
        when(
          () => platform.getCurrentPosition(
            locationSettings: any(named: 'locationSettings'),
          ),
        ).thenAnswer((_) async => position(accuracy: accuracy));
        when(
          () => platform.getLastKnownPosition(),
        ).thenAnswer((_) async => position(accuracy: accuracy));
        expect((await provider.currentFix()).accuracyMeters, isNull);
        expect((await provider.lastKnownFix())!.accuracyMeters, isNull);
      }
    },
  );

  test('unexpected plugin failures remain visible', () async {
    when(
      () => platform.getCurrentPosition(
        locationSettings: any(named: 'locationSettings'),
      ),
    ).thenThrow(StateError('unexpected'));
    await expectLater(provider.currentFix(), throwsStateError);
  });

  test('rejects nonpositive timeouts', () {
    expect(
      () => provider.currentFix(timeout: Duration.zero),
      throwsArgumentError,
    );
    expect(
      () => provider.currentFix(timeout: const Duration(seconds: -1)),
      throwsArgumentError,
    );
    verifyNever(() => platform.isLocationServiceEnabled());
  });
}
