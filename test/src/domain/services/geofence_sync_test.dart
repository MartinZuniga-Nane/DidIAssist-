import 'package:did_i_assist/src/domain/location/geofence_registration_id.dart';
import 'package:did_i_assist/src/domain/models/place.dart';
import 'package:did_i_assist/src/domain/services/geofence_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../location/mocks.dart';
import 'fixtures.dart';

void main() {
  late MockPlaceRepository places;
  late MockGeofenceRegistrar registrar;
  late Set<String> registered;
  late GeofenceSync sync;

  setUpAll(() => registerFallbackValue(homePlace()));
  setUp(() {
    places = MockPlaceRepository();
    registrar = MockGeofenceRegistrar();
    registered = {};
    when(
      () => places.getAll(),
    ).thenAnswer((_) async => [homePlace(), campusPlace()]);
    when(
      () => registrar.registeredIds(),
    ).thenAnswer((_) async => registered.toSet());
    when(() => registrar.register(any())).thenAnswer((invocation) async {
      registered.add(
        GeofenceRegistrationId.forPlace(
          invocation.positionalArguments.single as Place,
        ),
      );
    });
    when(() => registrar.unregister(any())).thenAnswer((invocation) async {
      registered.remove(invocation.positionalArguments.single);
    });
    sync = GeofenceSync(placeRepository: places, registrar: registrar);
  });

  test(
    'registers every home and campus and is idempotent on the second run',
    () async {
      await sync.sync();
      verify(() => registrar.register(homePlace())).called(1);
      verify(() => registrar.register(campusPlace())).called(1);
      clearInteractions(registrar);
      await sync.sync();
      verify(() => registrar.registeredIds()).called(1);
      verifyNever(() => registrar.register(any()));
      verifyNever(() => registrar.unregister(any()));
    },
  );

  test(
    'keeps unchanged registrations and registers only missing places',
    () async {
      registered.add(GeofenceRegistrationId.forPlace(homePlace()));
      await sync.sync();
      verifyNever(() => registrar.register(homePlace()));
      verify(() => registrar.register(campusPlace())).called(1);
      verifyNever(() => registrar.unregister(any()));
    },
  );

  test('unregisters deleted places without touching unrelated IDs', () async {
    final deleted = GeofenceRegistrationId.forPlace(homePlace(id: 'deleted'));
    registered.addAll([
      deleted,
      'other-feature:zone',
      'home',
      'didiassist:v1:invalid',
    ]);
    await sync.sync();
    verify(() => registrar.unregister(deleted)).called(1);
    expect(
      registered,
      containsAll(['other-feature:zone', 'home', 'didiassist:v1:invalid']),
    );
    verifyNever(() => registrar.unregister('other-feature:zone'));
    verifyNever(() => registrar.unregister('home'));
    verifyNever(() => registrar.unregister('didiassist:v1:invalid'));
  });

  final changes = {
    'radius': homePlace().copyWith(radiusMeters: 200),
    'latitude': homePlace().copyWith(
      center: eiffelTower().copyWith(latitude: 48.8585),
    ),
    'longitude': homePlace().copyWith(
      center: eiffelTower().copyWith(longitude: 2.2946),
    ),
  };
  for (final entry in changes.entries) {
    test(
      're-registers changed ${entry.key} even in a new sync instance',
      () async {
        final previous = GeofenceRegistrationId.forPlace(homePlace());
        registered.add(previous);
        when(() => places.getAll()).thenAnswer((_) async => [entry.value]);
        await sync.sync();
        verifyInOrder([
          () => registrar.unregister(previous),
          () => registrar.register(entry.value),
        ]);
        expect(registered, {GeofenceRegistrationId.forPlace(entry.value)});
        clearInteractions(registrar);
        await GeofenceSync(
          placeRepository: places,
          registrar: registrar,
        ).sync();
        verifyNever(() => registrar.register(any()));
        verifyNever(() => registrar.unregister(any()));
      },
    );
  }

  test('renaming a place does not change its geofence', () async {
    registered.add(GeofenceRegistrationId.forPlace(homePlace()));
    when(
      () => places.getAll(),
    ).thenAnswer((_) async => [homePlace().copyWith(name: 'Renamed')]);
    await sync.sync();
    verifyNever(() => registrar.register(any()));
    verifyNever(() => registrar.unregister(any()));
  });

  test('empty places remove owned registrations only', () async {
    final homeId = GeofenceRegistrationId.forPlace(homePlace());
    registered.addAll([homeId, 'unrelated']);
    when(() => places.getAll()).thenAnswer((_) async => []);
    await sync.sync();
    expect(registered, {'unrelated'});
    verify(() => registrar.unregister(homeId)).called(1);
    verifyNever(() => registrar.register(any()));
  });

  test(
    'obsolete fingerprints are removed even if a current one exists',
    () async {
      final home = homePlace();
      final old = GeofenceRegistrationId.forPlace(
        home.copyWith(radiusMeters: 200),
      );
      registered.addAll([old, GeofenceRegistrationId.forPlace(home)]);
      when(() => places.getAll()).thenAnswer((_) async => [home]);
      await sync.sync();
      verify(() => registrar.unregister(old)).called(1);
      verifyNever(() => registrar.register(any()));
    },
  );

  test(
    'registration errors propagate and missing registrations can be retried',
    () async {
      when(
        () => registrar.register(homePlace()),
      ).thenThrow(Exception('unavailable'));
      when(() => places.getAll()).thenAnswer((_) async => [homePlace()]);
      await expectLater(sync.sync(), throwsException);
      expect(registered, isEmpty);
      when(() => registrar.register(homePlace())).thenAnswer((_) async {
        registered.add(GeofenceRegistrationId.forPlace(homePlace()));
      });
      await sync.sync();
      expect(registered, hasLength(1));
    },
  );
}
