import 'package:did_i_assist/src/domain/location/geofence_registration_id.dart';
import 'package:did_i_assist/src/platform/background_location_callback.dart';
import 'package:did_i_assist/src/platform/native_geofence_registrar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:native_geofence/native_geofence.dart' as native;

import '../domain/services/fixtures.dart';

final class MockNativeGeofenceManager extends Mock
    implements native.NativeGeofenceManager {}

@pragma('vm:entry-point')
Future<void> bootstrapCallback(native.GeofenceCallbackParams params) async {}

void main() {
  late MockNativeGeofenceManager manager;
  late NativeGeofenceRegistrar registrar;

  setUpAll(() {
    registerFallbackValue(
      const native.Geofence(
        id: 'fallback',
        location: native.Location(latitude: 48.8584, longitude: 2.2945),
        radiusMeters: 150,
        triggers: {native.GeofenceEvent.enter},
        iosSettings: native.IosGeofenceSettings(),
        androidSettings: native.AndroidGeofenceSettings(initialTriggers: {}),
      ),
    );
    registerFallbackValue(nativeGeofenceCallback);
  });
  setUp(() {
    manager = MockNativeGeofenceManager();
    when(() => manager.initialize()).thenAnswer((_) async {});
    when(() => manager.getRegisteredGeofenceIds()).thenAnswer((_) async => []);
    when(() => manager.createGeofence(any(), any())).thenAnswer((_) async {});
    when(() => manager.removeGeofenceById(any())).thenAnswer((_) async {});
    registrar = NativeGeofenceRegistrar(manager: manager);
  });

  test(
    'maps place geometry, enter/exit/dwell, initial enter and two-minute settings',
    () async {
      final place = campusPlace();
      await registrar.register(place);
      final geofence =
          verify(
                () => manager.createGeofence(
                  captureAny(),
                  nativeGeofenceCallback,
                ),
              ).captured.single
              as native.Geofence;
      expect(geofence.id, GeofenceRegistrationId.forPlace(place));
      expect(geofence.location.latitude, place.center.latitude);
      expect(geofence.location.longitude, place.center.longitude);
      expect(geofence.radiusMeters, place.radiusMeters);
      expect(geofence.triggers, native.GeofenceEvent.values.toSet());
      expect(geofence.iosSettings.initialTrigger, isTrue);
      expect(geofence.androidSettings.initialTriggers, {
        native.GeofenceEvent.enter,
      });
      expect(
        geofence.androidSettings.loiteringDelay,
        const Duration(minutes: 2),
      );
      expect(
        geofence.androidSettings.notificationResponsiveness,
        const Duration(minutes: 2),
      );
      expect(geofence.androidSettings.expiration, isNull);
    },
  );

  test(
    'lists raw OS IDs and initializes the plugin once across operations',
    () async {
      final id = GeofenceRegistrationId.forPlace(homePlace());
      when(
        () => manager.getRegisteredGeofenceIds(),
      ).thenAnswer((_) async => [id, 'unrelated', id]);
      expect(await registrar.registeredIds(), {id, 'unrelated'});
      await registrar.register(homePlace());
      await registrar.unregister(id);
      verify(() => manager.initialize()).called(1);
      verify(() => manager.removeGeofenceById(id)).called(1);
    },
  );

  test(
    'unregistering unrelated or malformed IDs never reaches the plugin',
    () async {
      await registrar.unregister('other-feature:zone');
      await registrar.unregister('didiassist:v1:invalid');
      verifyNever(() => manager.initialize());
      verifyNever(() => manager.removeGeofenceById(any()));
    },
  );

  test('failed initialization can be retried and errors propagate', () async {
    var attempts = 0;
    when(() => manager.initialize()).thenAnswer((_) async {
      if (++attempts == 1) {
        throw native.NativeGeofenceException.internal(message: 'unavailable');
      }
    });
    await expectLater(
      registrar.registeredIds(),
      throwsA(isA<native.NativeGeofenceException>()),
    );
    expect(await registrar.registeredIds(), isEmpty);
    expect(attempts, 2);
  });

  test(
    'supports an app-provided top-level background bootstrap callback',
    () async {
      final custom = NativeGeofenceRegistrar(
        manager: manager,
        callback: bootstrapCallback,
      );
      await custom.register(homePlace());
      verify(() => manager.createGeofence(any(), bootstrapCallback)).called(1);
    },
  );
}
