import 'package:did_i_attend/src/domain/models/models.dart';
import 'package:did_i_attend/src/domain/services/trip_detector.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  const detector = TripDetector();
  final departure = DateTime(2026, 10, 5, 8);
  final exit = transition(LocationEventType.geofenceExit, departure);
  final enter = transition(
    LocationEventType.geofenceEnter,
    departure.add(const Duration(minutes: 30)),
    placeId: 'campus',
  );
  final places = [homePlace(), campusPlace()];

  test('detects a simple commute without requiring an earlier home enter', () {
    final trip = detector.detect(events: [exit, enter], places: places).single;
    expect(trip.fromPlaceId, 'home');
    expect(trip.toPlaceId, 'campus');
    expect(trip.departedAt, departure.toUtc());
    expect(trip.arrivedAt, enter.recordedAt);
    expect(trip.duration, const Duration(minutes: 30));
    expect(trip.mode, isNull);
    expect(trip.id.trim(), isNotEmpty);
  });

  for (final type in [
    LocationEventType.geofenceEnter,
    LocationEventType.geofenceDwell,
  ]) {
    test('home ${type.name} resets departure to the later exit', () {
      final laterExit = exit.copyWith(
        id: 'later-exit',
        recordedAt: departure.add(const Duration(minutes: 15)),
      );
      final trip = detector
          .detect(
            events: [
              exit,
              transition(type, departure.add(const Duration(minutes: 10))),
              laterExit,
              enter,
            ],
            places: places,
          )
          .single;
      expect(trip.departedAt, laterExit.recordedAt);
      expect(trip.duration, const Duration(minutes: 15));
    });
  }

  test('home re-entry without another exit cancels the commute', () {
    expect(
      detector.detect(
        events: [
          exit,
          transition(
            LocationEventType.geofenceEnter,
            departure.add(const Duration(minutes: 10)),
          ),
          enter,
        ],
        places: places,
      ),
      isEmpty,
    );
  });

  test('rejects a commute crossing local midnight with UTC events', () {
    final lateDeparture = DateTime(2026, 10, 5, 23, 50);
    expect(
      detector.detect(
        events: [
          exit.copyWith(recordedAt: lateDeparture.toUtc()),
          enter.copyWith(
            recordedAt: lateDeparture.add(const Duration(minutes: 30)).toUtc(),
          ),
        ],
        places: places,
      ),
      isEmpty,
    );
  });

  const durations = [
    (Duration(minutes: 3), true),
    (Duration(minutes: 180), true),
    (Duration(minutes: 3, microseconds: -1), false),
    (Duration(minutes: 180, microseconds: 1), false),
    (Duration.zero, false),
  ];
  for (final (duration, valid) in durations) {
    test('duration $duration valid = $valid', () {
      final trips = detector.detect(
        events: [
          exit,
          enter.copyWith(recordedAt: departure.add(duration)),
        ],
        places: places,
      );
      expect(trips.length, valid ? 1 : 0);
    });
  }

  test('campus dwell is an arrival and only the first arrival is used', () {
    final dwell = enter.copyWith(type: LocationEventType.geofenceDwell);
    final trips = detector.detect(
      events: [
        exit,
        dwell,
        enter.copyWith(recordedAt: departure.add(const Duration(minutes: 40))),
      ],
      places: places,
    );
    expect(trips.single.arrivedAt, dwell.recordedAt);
  });

  test('an invalid first arrival still consumes the departure', () {
    expect(
      detector.detect(
        events: [
          exit,
          enter.copyWith(recordedAt: departure.add(const Duration(minutes: 2))),
          enter,
        ],
        places: places,
      ),
      isEmpty,
    );
  });

  test('unordered events, duplicate transitions and exits keep stable IDs', () {
    final baseline = detector.detect(events: [exit, enter], places: places);
    final events = [
      enter,
      exit,
      exit,
      exit.copyWith(
        id: 'duplicate-exit',
        recordedAt: departure.add(const Duration(minutes: 5)),
      ),
      enter.copyWith(id: 'duplicate-enter'),
    ];
    expect(detector.detect(events: events, places: places.reversed), baseline);
    expect(detector.detect(events: events.reversed, places: places), baseline);
    expect(detector.detect(events: [exit, enter], places: places), baseline);
  });

  test('position samples and unknown places cannot alter transitions', () {
    final sampleAtHome = LocationEvent(
      id: 'sample-home',
      type: LocationEventType.positionSample,
      placeId: 'home',
      position: eiffelTower(),
      recordedAt: departure.add(const Duration(minutes: 5)),
    );
    final sampleAtCampus = sampleAtHome.copyWith(
      id: 'sample-campus',
      position: louvre,
      placeId: () => 'campus',
      recordedAt: departure.add(const Duration(minutes: 10)),
    );
    final trip = detector
        .detect(
          events: [
            exit,
            sampleAtHome,
            sampleAtCampus,
            transition(
              LocationEventType.geofenceEnter,
              departure.add(const Duration(minutes: 15)),
              placeId: 'unknown',
            ),
            transition(
              LocationEventType.geofenceExit,
              departure.add(const Duration(minutes: 20)),
              placeId: 'campus',
            ),
            enter,
          ],
          places: places,
        )
        .single;
    expect(trip.duration, const Duration(minutes: 30));
    expect(
      detector.detect(events: [exit, sampleAtCampus], places: places),
      isEmpty,
    );
    expect(
      detector.detect(events: [sampleAtHome, enter], places: places),
      isEmpty,
    );
  });

  test('missing home, campus, departure or arrival yields no trips', () {
    for (final available in [
      <Place>[],
      [homePlace()],
      [campusPlace()],
    ]) {
      expect(
        detector.detect(events: [exit, enter], places: available),
        isEmpty,
      );
    }
    for (final events in [
      <LocationEvent>[],
      [exit],
      [enter],
    ]) {
      expect(detector.detect(events: events, places: places), isEmpty);
    }
  });

  test('records separate departures and ignores campus to home travel', () {
    final trips = detector.detect(
      events: [
        exit,
        enter,
        transition(
          LocationEventType.geofenceExit,
          departure.add(const Duration(hours: 1)),
          placeId: 'campus',
        ),
        transition(
          LocationEventType.geofenceEnter,
          departure.add(const Duration(hours: 2)),
        ),
        exit.copyWith(
          id: 'second-exit',
          recordedAt: departure.add(const Duration(hours: 3)),
        ),
        enter.copyWith(
          id: 'second-enter',
          recordedAt: departure.add(const Duration(hours: 3, minutes: 30)),
        ),
      ],
      places: places,
    );
    expect(trips, hasLength(2));
    expect(trips.map((trip) => trip.id).toSet(), hasLength(2));
    expect(trips.every((trip) => trip.fromPlaceId == 'home'), isTrue);
  });

  test('uses the actual home and first campus for each commute', () {
    final secondHome = homePlace(id: 'other-home');
    final secondCampus = campusPlace(id: 'other-campus');
    final trip = detector
        .detect(
          events: [
            exit.copyWith(placeId: () => secondHome.id),
            enter.copyWith(placeId: () => secondCampus.id),
            enter.copyWith(
              recordedAt: departure.add(const Duration(minutes: 40)),
            ),
          ],
          places: [...places, secondHome, secondCampus],
        )
        .single;
    expect(trip.fromPlaceId, secondHome.id);
    expect(trip.toPlaceId, secondCampus.id);
  });
}
