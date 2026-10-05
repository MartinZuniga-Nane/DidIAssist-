import 'package:clock/clock.dart';
import 'package:did_i_assist/src/domain/location/geofence_transition.dart';
import 'package:did_i_assist/src/domain/models/location_event_type.dart';
import 'package:did_i_assist/src/platform/background_location_callback.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../domain/location/mocks.dart';
import 'fixtures.dart';

void main() {
  final receipt = DateTime.utc(2026, 10, 5, 9);
  late MockBackgroundLocationHandler handler;

  setUpAll(
    () => registerFallbackValue(
      GeofenceTransition(
        placeIds: const ['campus'],
        type: LocationEventType.geofenceEnter,
        receivedAt: receipt,
      ),
    ),
  );
  setUp(() {
    BackgroundLocationRegistry.clear();
    handler = MockBackgroundLocationHandler();
    when(() => handler.handle(any())).thenAnswer((_) async {});
  });
  tearDown(BackgroundLocationRegistry.clear);

  test(
    'dispatches mapped params to the registered handler using its clock',
    () async {
      expect(BackgroundLocationRegistry.isRegistered, isFalse);
      BackgroundLocationRegistry.register(
        handler,
        timeSource: Clock.fixed(receipt),
      );
      expect(BackgroundLocationRegistry.isRegistered, isTrue);
      await nativeGeofenceCallback(callbackParams());
      final transition =
          verify(() => handler.handle(captureAny())).captured.single
              as GeofenceTransition;
      expect(transition.placeIds, ['campus']);
      expect(transition.type, LocationEventType.geofenceEnter);
      expect(transition.receivedAt, receipt);
    },
  );

  test(
    'registration can be replaced and cleared for isolate bootstrap',
    () async {
      final replacement = MockBackgroundLocationHandler();
      when(() => replacement.handle(any())).thenAnswer((_) async {});
      BackgroundLocationRegistry.register(handler);
      BackgroundLocationRegistry.register(
        replacement,
        timeSource: Clock.fixed(receipt),
      );
      await nativeGeofenceCallback(callbackParams());
      verify(() => replacement.handle(any())).called(1);
      verifyNever(() => handler.handle(any()));
      BackgroundLocationRegistry.clear();
      expect(BackgroundLocationRegistry.isRegistered, isFalse);
      await expectLater(
        nativeGeofenceCallback(callbackParams()),
        throwsStateError,
      );
    },
  );

  test(
    'missing registration fails explicitly',
    () async {
      await expectLater(
        nativeGeofenceCallback(callbackParams()),
        throwsStateError,
      );
    },
  );

  test('unrelated callbacks need no handler and do not dispatch', () async {
    await nativeGeofenceCallback(callbackParams(geofences: []));
    BackgroundLocationRegistry.register(handler);
    await nativeGeofenceCallback(
      callbackParams(
        geofences: [
          activeGeofence(registrationId: 'unrelated'),
        ],
      ),
    );
    verifyNever(() => handler.handle(any()));
  });

  test('awaits the handler and propagates persistence failures', () async {
    BackgroundLocationRegistry.register(handler);
    when(
      () => handler.handle(any()),
    ).thenThrow(Exception('storage unavailable'));
    await expectLater(
      nativeGeofenceCallback(callbackParams()),
      throwsException,
    );
  });

  test('without an explicit clock honors the scoped package clock', () async {
    BackgroundLocationRegistry.register(handler);
    await withClock(
      Clock.fixed(receipt),
      () => nativeGeofenceCallback(callbackParams()),
    );
    final transition =
        verify(() => handler.handle(captureAny())).captured.single
            as GeofenceTransition;
    expect(transition.receivedAt, receipt);
  });
}
