import 'package:clock/clock.dart';
import 'package:did_i_assist/src/domain/models/models.dart';
import 'package:did_i_assist/src/domain/services/departure_advisor.dart';
import 'package:did_i_assist/src/domain/services/departure_service.dart';
import 'package:did_i_assist/src/domain/services/eta_estimator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';
import 'in_memory_repositories.dart';

void main() {
  final now = DateTime(2026, 10, 5, 8);
  final classOccurrence = occurrence();
  late InMemoryPlaceRepository places;
  late InMemorySettingsRepository settings;
  late InMemoryTripRepository trips;
  late DepartureService service;

  setUp(() {
    places = InMemoryPlaceRepository([homePlace(), campusPlace()]);
    settings = InMemorySettingsRepository();
    trips = InMemoryTripRepository();
    service = DepartureService(
      placeRepository: places,
      settingsRepository: settings,
      tripRepository: trips,
      timeSource: Clock.fixed(now),
    );
  });

  test(
    'default settings use walking, five-minute buffer and home fallback',
    () async {
      final advice = (await service.adviseFor(classOccurrence))!;
      expect(advice.status, DepartureStatus.onTime);
      expect(advice.eta.duration, const Duration(minutes: 52));
      expect(advice.eta.source, EtaSource.heuristic);
      expect(advice.eta.sampleSize, 0);
      expect(advice.expectedArrival, DateTime(2026, 10, 5, 8, 52));
      expect(advice.leaveBy, DateTime(2026, 10, 5, 8, 3));
      expect(advice.originKind, OriginKind.home);
      expect(settings.loadCount, 1);
      expect(trips.queries.single, ('home', 'campus', null));
      expect(trips.added, isEmpty);
    },
  );

  test('loads the saved travel mode and departure buffer', () async {
    await settings.save(
      UserSettings(
        defaultTravelMode: TravelMode.transit,
        departureBufferMinutes: 10,
      ),
    );
    final advice = (await service.adviseFor(classOccurrence))!;
    expect(advice.eta.duration, const Duration(minutes: 22));
    expect(advice.leaveBy, DateTime(2026, 10, 5, 8, 28));
    expect(advice.expectedArrival, DateTime(2026, 10, 5, 8, 22));
  });

  test('current position is used in preference to home', () async {
    final advice = (await service.adviseFor(
      classOccurrence,
      currentPosition: arcDeTriomphe(),
    ))!;
    expect(advice.originKind, OriginKind.currentPosition);
    expect(advice.eta.duration, const Duration(minutes: 56));
    expect(advice.status, DepartureStatus.leaveNow);
    expect(advice.leaveBy, DateTime(2026, 10, 5, 7, 59));
  });

  test(
    'without a home a current position still gets heuristic advice',
    () async {
      await places.delete('home');
      final advice = (await service.adviseFor(
        classOccurrence,
        currentPosition: eiffelTower(),
      ))!;
      expect(advice.originKind, OriginKind.currentPosition);
      expect(advice.eta.duration, const Duration(minutes: 52));
      expect(advice.eta.source, EtaSource.heuristic);
      expect(trips.queries, isEmpty);
    },
  );

  test('without a current position or home returns null', () async {
    await places.delete('home');
    expect(await service.adviseFor(classOccurrence), isNull);
    expect(settings.loadCount, 0);
    expect(trips.queries, isEmpty);
  });

  test(
    'multiple homes use the first by ID regardless of repository order',
    () async {
      places.places.clear();
      await places.save(homePlace(id: 'z-home').copyWith(center: bigBen()));
      await places.save(campusPlace());
      await places.save(homePlace(id: 'a-home'));
      for (var i = 0; i < 5; i++) {
        await trips.add(
          commute(
            id: 'a-trip-$i',
            fromPlaceId: 'a-home',
            duration: const Duration(minutes: 20),
          ),
        );
        await trips.add(
          commute(
            id: 'z-trip-$i',
            fromPlaceId: 'z-home',
            duration: const Duration(minutes: 180),
          ),
        );
      }
      final advice = (await service.adviseFor(classOccurrence))!;
      expect(trips.queries.single, ('a-home', 'campus', null));
      expect(advice.eta.duration, const Duration(minutes: 20));
      expect(advice.eta.source, EtaSource.learned);
      expect(advice.eta.sampleSize, 5);
      expect(advice.originKind, OriginKind.home);
    },
  );

  test(
    'valid trips are filtered before the last-ten window in the service',
    () async {
      for (var i = 0; i < 12; i++) {
        await trips.add(
          commute(
            id: 'valid-$i',
            duration: Duration(minutes: 10 + i),
            arrivedAt: DateTime(2026, 9, i + 1, 9),
          ),
        );
        await trips.add(
          commute(
            id: 'invalid-$i',
            duration: const Duration(minutes: 181),
            arrivedAt: DateTime(2026, 9, i + 13, 9),
          ),
        );
      }
      await trips.add(
        commute(
          id: 'other-campus',
          toPlaceId: 'other-campus',
          duration: const Duration(minutes: 180),
        ),
      );
      final advice = (await service.adviseFor(classOccurrence))!;
      expect(trips.queries.single.$3, isNull);
      expect(advice.eta.sampleSize, 10);
      expect(advice.eta.duration, const Duration(minutes: 16, seconds: 30));
      expect(advice.eta.source, EtaSource.learned);
      expect(advice.leaveBy, DateTime(2026, 10, 5, 8, 38, 30));
    },
  );

  test('three samples blend at home and calibrate other origins', () async {
    for (var i = 0; i < 3; i++) {
      await trips.add(
        commute(
          id: 'trip-$i',
          duration: const Duration(minutes: 39),
        ),
      );
    }
    final homeAdvice = (await service.adviseFor(classOccurrence))!;
    expect(homeAdvice.eta.duration, const Duration(minutes: 48));
    expect(homeAdvice.eta.source, EtaSource.blended);
    final otherAdvice = (await service.adviseFor(
      classOccurrence,
      currentPosition: arcDeTriomphe(),
    ))!;
    expect(otherAdvice.eta.duration, const Duration(minutes: 42));
    expect(otherAdvice.eta.source, EtaSource.blended);
  });

  test('inside campus returns alreadyThere even after the start', () async {
    final laterService = DepartureService(
      placeRepository: places,
      settingsRepository: settings,
      tripRepository: trips,
      timeSource: Clock.fixed(DateTime(2026, 10, 5, 9, 30)),
    );
    final advice = (await laterService.adviseFor(
      classOccurrence,
      currentPosition: louvre(),
    ))!;
    expect(advice.status, DepartureStatus.alreadyThere);
    expect(advice.eta.duration, Duration.zero);
    expect(advice.lateBy, Duration.zero);
  });

  test('injected clock drives late advice with a rounded delay', () async {
    final laterService = DepartureService(
      placeRepository: places,
      settingsRepository: settings,
      tripRepository: trips,
      timeSource: Clock.fixed(DateTime(2026, 10, 5, 8, 8, 1)),
    );
    final advice = (await laterService.adviseFor(classOccurrence))!;
    expect(advice.status, DepartureStatus.late);
    expect(advice.lateBy, const Duration(minutes: 1));
    expect(advice.expectedArrival, DateTime(2026, 10, 5, 9, 0, 1));
  });

  test('uses the destination supplied by the occurrence', () async {
    await places.delete('campus');
    final advice = (await service.adviseFor(classOccurrence))!;
    expect(advice.eta.duration, const Duration(minutes: 52));
    expect(trips.queries.single.$2, classOccurrence.place.id);
  });
}
