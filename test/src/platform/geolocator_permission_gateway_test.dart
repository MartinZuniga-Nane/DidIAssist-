import 'package:did_i_assist/src/domain/location/location_permission_gateway.dart';
import 'package:did_i_assist/src/platform/geolocator_permission_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mocktail/mocktail.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;

final class MockGeolocatorPlatform extends Mock
    implements geo.GeolocatorPlatform {}

void main() {
  late MockGeolocatorPlatform platform;
  late GeolocatorPermissionGateway gateway;
  late int alwaysRequests;
  late permissions.PermissionStatus alwaysStatus;
  late List<String> requestOrder;

  setUp(() {
    platform = MockGeolocatorPlatform();
    alwaysRequests = 0;
    alwaysStatus = permissions.PermissionStatus.granted;
    requestOrder = [];
    when(
      () => platform.isLocationServiceEnabled(),
    ).thenAnswer((_) async => true);
    when(
      () => platform.checkPermission(),
    ).thenAnswer((_) async => geo.LocationPermission.denied);
    when(() => platform.requestPermission()).thenAnswer((_) async {
      requestOrder.add('foreground');
      return geo.LocationPermission.whileInUse;
    });
    gateway = GeolocatorPermissionGateway(
      platform: platform,
      requestAlways: () async {
        requestOrder.add('background');
        alwaysRequests++;
        return alwaysStatus;
      },
    );
  });

  const states = {
    geo.LocationPermission.denied: LocationPermissionStatus.denied,
    geo.LocationPermission.deniedForever:
        LocationPermissionStatus.deniedForever,
    geo.LocationPermission.whileInUse: LocationPermissionStatus.whileInUse,
    geo.LocationPermission.always: LocationPermissionStatus.always,
    geo.LocationPermission.unableToDetermine: LocationPermissionStatus.denied,
  };
  for (final entry in states.entries) {
    test('check maps ${entry.key}', () async {
      when(() => platform.checkPermission()).thenAnswer((_) async => entry.key);
      expect(await gateway.check(), entry.value);
    });
  }

  test(
    'disabled service takes precedence and does not request permissions',
    () async {
      when(
        () => platform.isLocationServiceEnabled(),
      ).thenAnswer((_) async => false);
      expect(await gateway.check(), LocationPermissionStatus.serviceDisabled);
      expect(
        await gateway.requestForeground(),
        LocationPermissionStatus.serviceDisabled,
      );
      expect(
        await gateway.requestBackground(),
        LocationPermissionStatus.serviceDisabled,
      );
      verifyNever(() => platform.checkPermission());
      verifyNever(() => platform.requestPermission());
      expect(alwaysRequests, 0);
    },
  );

  test('foreground request never asks for background permission', () async {
    expect(
      await gateway.requestForeground(),
      LocationPermissionStatus.whileInUse,
    );
    verify(() => platform.requestPermission()).called(1);
    expect(alwaysRequests, 0);
  });

  test(
    'background request obtains foreground permission before always',
    () async {
      expect(
        await gateway.requestBackground(),
        LocationPermissionStatus.always,
      );
      expect(requestOrder, ['foreground', 'background']);
      expect(alwaysRequests, 1);
    },
  );

  test(
    'upgrades while-in-use without another foreground request',
    () async {
      when(
        () => platform.checkPermission(),
      ).thenAnswer((_) async => geo.LocationPermission.whileInUse);
      expect(
        await gateway.requestBackground(),
        LocationPermissionStatus.always,
      );
      expect(alwaysRequests, 1);
      verifyNever(() => platform.requestPermission());
    },
  );

  for (final status in [
    geo.LocationPermission.denied,
    geo.LocationPermission.deniedForever,
  ]) {
    test(
      'foreground refusal $status does not attempt background access',
      () async {
        when(
          () => platform.requestPermission(),
        ).thenAnswer((_) async => status);
        expect(await gateway.requestBackground(), states[status]);
        expect(alwaysRequests, 0);
      },
    );
  }

  test('denied forever is checked without prompting again', () async {
    when(
      () => platform.checkPermission(),
    ).thenAnswer((_) async => geo.LocationPermission.deniedForever);
    expect(
      await gateway.requestForeground(),
      LocationPermissionStatus.deniedForever,
    );
    expect(
      await gateway.requestBackground(),
      LocationPermissionStatus.deniedForever,
    );
    verifyNever(() => platform.requestPermission());
    expect(alwaysRequests, 0);
  });

  test('an always grant is retained without any new request', () async {
    when(
      () => platform.checkPermission(),
    ).thenAnswer((_) async => geo.LocationPermission.always);
    expect(await gateway.requestForeground(), LocationPermissionStatus.always);
    expect(await gateway.requestBackground(), LocationPermissionStatus.always);
    verifyNever(() => platform.requestPermission());
    expect(alwaysRequests, 0);
  });

  test('refusing always preserves while-in-use access', () async {
    when(
      () => platform.checkPermission(),
    ).thenAnswer((_) async => geo.LocationPermission.whileInUse);
    for (final status in [
      permissions.PermissionStatus.denied,
      permissions.PermissionStatus.permanentlyDenied,
      permissions.PermissionStatus.restricted,
    ]) {
      alwaysStatus = status;
      expect(
        await gateway.requestBackground(),
        LocationPermissionStatus.whileInUse,
      );
    }
    expect(alwaysRequests, 3);
  });

  test(
    'opens app or location settings and returns the plugin result',
    () async {
      when(() => platform.openAppSettings()).thenAnswer((_) async => false);
      when(() => platform.openLocationSettings()).thenAnswer((_) async => true);
      expect(await gateway.openSettings(), isFalse);
      expect(await gateway.openSettings(locationServices: true), isTrue);
      verify(() => platform.openAppSettings()).called(1);
      verify(() => platform.openLocationSettings()).called(1);
    },
  );
}
