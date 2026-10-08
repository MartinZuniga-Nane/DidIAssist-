import 'dart:math';

import 'package:did_i_attend/src/core/geo.dart';
import 'package:did_i_attend/src/core/geo_point.dart';
import 'package:did_i_attend/src/domain/models/models.dart';
import 'package:did_i_attend/src/domain/services/attendance_evaluation.dart';
import 'package:did_i_attend/src/domain/services/attendance_evaluator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../models/fixtures.dart' as fixtures;

void main() {
  final occurrence = fixtures.sampleOccurrence();
  final start = occurrence.start;
  final end = occurrence.end;
  final windowStart = start.subtract(const Duration(minutes: 15));
  final historyStart = windowStart.subtract(const Duration(hours: 12));
  final point = fixtures.samplePoint();
  final bigBen = GeoPoint(latitude: 51.5007, longitude: -0.1246);
  final pontIena = GeoPoint(latitude: 48.8573, longitude: 2.2918);
  final defaultPolicy = AttendancePolicy();

  LocationEvent event(
    DateTime at, {
    LocationEventType type = LocationEventType.geofenceEnter,
    String placeId = fixtures.placeId,
    GeoPoint? position,
    double? accuracy,
    String id = fixtures.recordId,
  }) => LocationEvent(
    id: id,
    type: type,
    placeId: type == LocationEventType.positionSample ? null : placeId,
    position: type == LocationEventType.positionSample
        ? position ?? point
        : null,
    accuracyMeters: accuracy,
    recordedAt: at,
  );

  final cases =
      <
        ({
          String name,
          List<LocationEvent> events,
          DateTime now,
          AttendanceStatus status,
          DateTime? checkInAt,
          AttendancePolicy? policy,
        })
      >[];

  void scenario(
    String name,
    List<LocationEvent> events,
    AttendanceStatus status, {
    DateTime? now,
    DateTime? checkInAt,
    AttendancePolicy? policy,
  }) => cases.add((
    name: name,
    events: events,
    now: now ?? end,
    status: status,
    checkInAt: checkInAt,
    policy: policy,
  ));

  scenario(
    'on-time enter is present',
    [event(start)],
    AttendanceStatus.present,
    checkInAt: start,
  );
  scenario(
    'exactly start plus grace is present',
    [event(start.add(const Duration(minutes: 10)))],
    AttendanceStatus.present,
    checkInAt: start.add(const Duration(minutes: 10)),
  );
  scenario(
    'one millisecond after grace is late',
    [event(start.add(const Duration(minutes: 10, milliseconds: 1)))],
    AttendanceStatus.late,
    checkInAt: start.add(const Duration(minutes: 10, milliseconds: 1)),
  );
  scenario(
    'late arrival before the default class-end cutoff is late',
    [event(start.add(const Duration(minutes: 30)))],
    AttendanceStatus.late,
    checkInAt: start.add(const Duration(minutes: 30)),
  );
  scenario(
    'exactly lateUntil is late',
    [event(start.add(const Duration(minutes: 30)))],
    AttendanceStatus.late,
    policy: AttendancePolicy(lateUntilMinutes: 30),
    checkInAt: start.add(const Duration(minutes: 30)),
  );
  scenario(
    'first arrival after lateUntil but before end is absent immediately',
    [event(start.add(const Duration(minutes: 30, milliseconds: 1)))],
    AttendanceStatus.absent,
    policy: AttendancePolicy(lateUntilMinutes: 30),
    now: start.add(const Duration(minutes: 31)),
    checkInAt: start.add(const Duration(minutes: 30, milliseconds: 1)),
  );
  scenario('no evidence at class end is absent', [], AttendanceStatus.absent);
  scenario(
    'no evidence long after class end is absent',
    [],
    AttendanceStatus.absent,
    now: end.add(const Duration(days: 30)),
  );
  scenario(
    'no evidence during an ongoing class is pending',
    [],
    AttendanceStatus.pending,
    now: start.add(const Duration(minutes: 30)),
  );
  scenario(
    'one microsecond before class end is pending',
    [],
    AttendanceStatus.pending,
    now: end.subtract(const Duration(microseconds: 1)),
  );
  scenario(
    'no evidence after lateUntil stays pending until class end',
    [],
    AttendanceStatus.pending,
    policy: AttendancePolicy(lateUntilMinutes: 30),
    now: start.add(const Duration(minutes: 60)),
  );
  scenario(
    'enter before the window without exit clamps check-in to window start',
    [event(windowStart.subtract(const Duration(minutes: 1)))],
    AttendanceStatus.present,
    checkInAt: windowStart,
  );
  scenario(
    'enter exactly at the carry-over cap is trusted',
    [event(historyStart)],
    AttendanceStatus.present,
    checkInAt: windowStart,
  );
  scenario('enter one microsecond older than the cap is stale', [
    event(historyStart.subtract(const Duration(microseconds: 1))),
  ], AttendanceStatus.absent);
  scenario(
    'a stale enter is refreshed by a recent dwell',
    [
      event(historyStart.subtract(const Duration(hours: 1))),
      event(
        windowStart.subtract(const Duration(minutes: 1)),
        type: LocationEventType.geofenceDwell,
      ),
    ],
    AttendanceStatus.present,
    checkInAt: windowStart,
  );
  scenario('exit before the window cancels carry-over', [
    event(windowStart.subtract(const Duration(minutes: 2))),
    event(
      windowStart.subtract(const Duration(minutes: 1)),
      type: LocationEventType.geofenceExit,
    ),
  ], AttendanceStatus.absent);
  scenario(
    'exit exactly at window start leaves no overlapping presence',
    [
      event(windowStart.subtract(const Duration(minutes: 2))),
      event(windowStart, type: LocationEventType.geofenceExit),
    ],
    AttendanceStatus.absent,
  );
  scenario(
    'exit after window start retains the earlier clamped check-in',
    [
      event(windowStart.subtract(const Duration(minutes: 2))),
      event(
        windowStart.add(const Duration(milliseconds: 1)),
        type: LocationEventType.geofenceExit,
      ),
    ],
    AttendanceStatus.present,
    checkInAt: windowStart,
  );
  scenario(
    'dwell alone is inside evidence',
    [event(start, type: LocationEventType.geofenceDwell)],
    AttendanceStatus.present,
    checkInAt: start,
  );
  scenario(
    'position sample with null accuracy uses zero accuracy',
    [event(start, type: LocationEventType.positionSample)],
    AttendanceStatus.present,
    checkInAt: start,
  );
  scenario(
    'sample at the maximum accepted accuracy is included',
    [event(start, type: LocationEventType.positionSample, accuracy: 200)],
    AttendanceStatus.present,
    checkInAt: start,
  );
  scenario('sample above maximum accuracy is ignored', [
    event(start, type: LocationEventType.positionSample, accuracy: 200.001),
  ], AttendanceStatus.absent);
  scenario(
    'reported accuracy expands the radius',
    [
      event(
        start,
        type: LocationEventType.positionSample,
        position: pontIena,
        accuracy: 100,
      ),
    ],
    AttendanceStatus.present,
    checkInAt: start,
  );
  scenario('null accuracy does not expand the radius', [
    event(start, type: LocationEventType.positionSample, position: pontIena),
  ], AttendanceStatus.absent);
  scenario(
    'outside position sample before the window acts as implicit exit',
    [
      event(windowStart.subtract(const Duration(minutes: 2))),
      event(
        windowStart.subtract(const Duration(minutes: 1)),
        type: LocationEventType.positionSample,
        position: bigBen,
      ),
    ],
    AttendanceStatus.absent,
  );
  scenario(
    'outside sample exactly at window start cancels carry-over',
    [
      event(windowStart.subtract(const Duration(minutes: 2))),
      event(
        windowStart,
        type: LocationEventType.positionSample,
        position: bigBen,
      ),
    ],
    AttendanceStatus.absent,
  );
  scenario(
    'inaccurate outside sample does not cancel trusted carry-over',
    [
      event(windowStart.subtract(const Duration(minutes: 2))),
      event(
        windowStart.subtract(const Duration(minutes: 1)),
        type: LocationEventType.positionSample,
        position: bigBen,
        accuracy: 201,
      ),
    ],
    AttendanceStatus.present,
    checkInAt: windowStart,
  );
  scenario(
    'outside sample after a check-in does not erase attendance',
    [
      event(start, type: LocationEventType.positionSample),
      event(
        start.add(const Duration(minutes: 1)),
        type: LocationEventType.positionSample,
        position: bigBen,
      ),
    ],
    AttendanceStatus.present,
    checkInAt: start,
  );
  scenario('other place enter and dwell are ignored', [
    event(start, placeId: fixtures.homeId),
    event(
      start.add(const Duration(minutes: 1)),
      type: LocationEventType.geofenceDwell,
      placeId: fixtures.homeId,
    ),
  ], AttendanceStatus.absent);
  scenario(
    'other place exit cannot cancel carry-over',
    [
      event(windowStart.subtract(const Duration(minutes: 2))),
      event(
        windowStart.subtract(const Duration(minutes: 1)),
        type: LocationEventType.geofenceExit,
        placeId: fixtures.homeId,
      ),
    ],
    AttendanceStatus.present,
    checkInAt: windowStart,
  );
  scenario(
    'future enter during an ongoing class is ignored',
    [event(start.add(const Duration(minutes: 1)))],
    AttendanceStatus.pending,
    now: start,
  );
  scenario(
    'future exit cannot erase known presence',
    [
      event(windowStart.subtract(const Duration(minutes: 1))),
      event(
        start.add(const Duration(minutes: 1)),
        type: LocationEventType.geofenceExit,
      ),
    ],
    AttendanceStatus.present,
    now: start,
    checkInAt: windowStart,
  );
  scenario(
    'evidence exactly at now is accepted',
    [event(start)],
    AttendanceStatus.present,
    now: start,
    checkInAt: start,
  );
  scenario(
    'one microsecond after now is never considered',
    [event(start.add(const Duration(microseconds: 1)))],
    AttendanceStatus.pending,
    now: start,
  );
  scenario(
    'before the window no check-in is predicted from prior inside state',
    [event(windowStart.subtract(const Duration(minutes: 1)))],
    AttendanceStatus.pending,
    now: windowStart.subtract(const Duration(microseconds: 1)),
  );
  scenario(
    'at window start trusted carry-over is present',
    [event(windowStart.subtract(const Duration(minutes: 1)))],
    AttendanceStatus.present,
    now: windowStart,
    checkInAt: windowStart,
  );
  scenario(
    'exactly at the default class-end cutoff is late',
    [event(end)],
    AttendanceStatus.late,
    checkInAt: end,
  );
  scenario(
    'one microsecond after class end is outside the attendance window',
    [event(end.add(const Duration(microseconds: 1)))],
    AttendanceStatus.absent,
    now: end.add(const Duration(hours: 1)),
  );
  scenario(
    're-entry after an outside sample uses the first new inside instant',
    [
      event(windowStart.subtract(const Duration(minutes: 2))),
      event(
        windowStart.subtract(const Duration(minutes: 1)),
        type: LocationEventType.positionSample,
        position: bigBen,
      ),
      event(start.add(const Duration(minutes: 20))),
    ],
    AttendanceStatus.late,
    checkInAt: start.add(const Duration(minutes: 20)),
  );
  scenario(
    'earlier attendance wins over a subsequent late re-entry',
    [
      event(start),
      event(
        start.add(const Duration(minutes: 1)),
        type: LocationEventType.geofenceExit,
      ),
      event(start.add(const Duration(minutes: 20))),
    ],
    AttendanceStatus.present,
    checkInAt: start,
  );
  scenario(
    'zero grace still includes an arrival exactly at start',
    [event(start)],
    AttendanceStatus.present,
    policy: AttendancePolicy(graceMinutes: 0),
    checkInAt: start,
  );
  scenario(
    'zero early window does not count an exited early arrival',
    [
      event(start.subtract(const Duration(minutes: 2))),
      event(
        start.subtract(const Duration(minutes: 1)),
        type: LocationEventType.geofenceExit,
      ),
    ],
    AttendanceStatus.absent,
    policy: AttendancePolicy(earlyWindowMinutes: 0),
  );

  for (final value in cases) {
    test(value.name, () {
      final expected = AttendanceEvaluation(
        status: value.status,
        checkInAt: value.checkInAt,
      );
      final input = value.events.toList();
      final original = input.toList();
      final evaluator = AttendanceEvaluator();
      for (final events in [
        input,
        input.reversed.toList(),
        input.toList()..shuffle(Random(42)),
      ]) {
        expect(
          evaluator.evaluate(
            occurrence: occurrence,
            place: occurrence.place,
            events: events,
            policy: value.policy ?? defaultPolicy,
            now: value.now,
          ),
          expected,
        );
      }
      expect(input, original);
    });
  }

  test(
    'same timestamp orders exits and outside samples before inside evidence',
    () {
      final conflicting = [
        event(
          windowStart.subtract(const Duration(milliseconds: 1)),
          type: LocationEventType.geofenceExit,
          id: fixtures.homeId,
        ),
        event(
          windowStart.subtract(const Duration(milliseconds: 1)),
          type: LocationEventType.positionSample,
          position: bigBen,
        ),
        event(
          windowStart.subtract(const Duration(milliseconds: 1)),
          id: fixtures.slotId,
        ),
        event(
          windowStart.subtract(const Duration(milliseconds: 1)),
          type: LocationEventType.geofenceDwell,
          id: fixtures.courseId,
        ),
        event(
          windowStart.subtract(const Duration(milliseconds: 1)),
          type: LocationEventType.positionSample,
          id: fixtures.placeId,
        ),
      ];
      for (final permutation in _permutations(conflicting)) {
        expect(
          AttendanceEvaluator().evaluate(
            occurrence: occurrence,
            place: occurrence.place,
            events: permutation,
            policy: defaultPolicy,
            now: end,
          ),
          AttendanceEvaluation(
            status: AttendanceStatus.present,
            checkInAt: windowStart,
          ),
        );
      }
    },
  );

  test('same-timestamp conflicting signals at window start favor presence', () {
    for (final at in [windowStart, start]) {
      expect(
        AttendanceEvaluator().evaluate(
          occurrence: occurrence,
          place: occurrence.place,
          events: [
            event(at),
            event(at, type: LocationEventType.geofenceExit),
            event(at, type: LocationEventType.positionSample, position: bigBen),
          ],
          policy: defaultPolicy,
          now: end,
        ),
        AttendanceEvaluation(status: AttendanceStatus.present, checkInAt: at),
      );
    }
  });

  test(
    'position samples are evaluated by distance regardless of their place ID',
    () {
      final tagged = event(
        start,
        type: LocationEventType.positionSample,
      ).copyWith(placeId: () => fixtures.homeId);
      expect(
        AttendanceEvaluator()
            .evaluate(
              occurrence: occurrence,
              place: occurrence.place,
              events: [tagged],
              policy: defaultPolicy,
              now: end,
            )
            .status,
        AttendanceStatus.present,
      );
    },
  );

  test(
    'a sample exactly on the radius is inside and just beyond it is outside',
    () {
      final radius = haversineDistanceMeters(point, pontIena);
      final sample = event(
        start,
        type: LocationEventType.positionSample,
        position: pontIena,
      );
      for (final value in [
        (radius: radius, status: AttendanceStatus.present),
        (radius: radius - 0.001, status: AttendanceStatus.absent),
      ]) {
        final place = occurrence.place.copyWith(radiusMeters: value.radius);
        expect(
          AttendanceEvaluator()
              .evaluate(
                occurrence: occurrence,
                place: place,
                events: [sample],
                policy: defaultPolicy,
                now: end,
              )
              .status,
          value.status,
        );
      }
    },
  );

  test('custom carry-over limits and zero carry-over are respected', () {
    final old = event(windowStart.subtract(const Duration(minutes: 61)));
    expect(
      AttendanceEvaluator(carryOver: const Duration(hours: 1))
          .evaluate(
            occurrence: occurrence,
            place: occurrence.place,
            events: [old],
            policy: defaultPolicy,
            now: end,
          )
          .status,
      AttendanceStatus.absent,
    );
    expect(
      AttendanceEvaluator(carryOver: Duration.zero)
          .evaluate(
            occurrence: occurrence,
            place: occurrence.place,
            events: [
              event(windowStart.subtract(const Duration(microseconds: 1))),
            ],
            policy: defaultPolicy,
            now: end,
          )
          .status,
      AttendanceStatus.absent,
    );
    expect(
      AttendanceEvaluator(carryOver: Duration.zero)
          .evaluate(
            occurrence: occurrence,
            place: occurrence.place,
            events: [event(windowStart)],
            policy: defaultPolicy,
            now: end,
          )
          .status,
      AttendanceStatus.present,
    );
  });

  test(
    'overnight attendance uses the actual local occurrence and UTC check-in',
    () {
      final overnight = ClassOccurrence.forDate(
        slot: fixtures.sampleSlot().copyWith(startMinute: 1410),
        course: fixtures.sampleCourse(),
        place: fixtures.samplePlace(),
        date: occurrence.occurrenceDate,
      );
      final arrived = DateTime(2026, 10, 6, 0, 1);
      expect(
        AttendanceEvaluator().evaluate(
          occurrence: overnight,
          place: overnight.place,
          events: [event(arrived)],
          policy: defaultPolicy,
          now: overnight.end,
        ),
        AttendanceEvaluation(status: AttendanceStatus.late, checkInAt: arrived),
      );
    },
  );

  test('overnight early evidence clamps to the previous calendar day', () {
    final overnight = ClassOccurrence.forDate(
      slot: fixtures.sampleSlot().copyWith(startMinute: 5),
      course: fixtures.sampleCourse(),
      place: fixtures.samplePlace(),
      date: occurrence.occurrenceDate,
    );
    final window = DateTime(2026, 10, 4, 23, 50);
    expect(
      AttendanceEvaluator()
          .evaluate(
            occurrence: overnight,
            place: overnight.place,
            events: [event(DateTime(2026, 10, 4, 23, 49))],
            policy: defaultPolicy,
            now: overnight.end,
          )
          .checkInAt,
      window.toUtc(),
    );
  });

  test('rejects a negative carry-over and a mismatched place', () {
    expect(
      () => AttendanceEvaluator(carryOver: const Duration(microseconds: -1)),
      throwsArgumentError,
    );
    expect(
      () => AttendanceEvaluator().evaluate(
        occurrence: occurrence,
        place: occurrence.place.copyWith(id: fixtures.homeId),
        events: [],
        policy: defaultPolicy,
        now: end,
      ),
      throwsArgumentError,
    );
  });
}

Iterable<List<T>> _permutations<T>(List<T> values) sync* {
  if (values.isEmpty) {
    yield <T>[];
    return;
  }
  for (var index = 0; index < values.length; index++) {
    final remainder = values.toList()..removeAt(index);
    for (final rest in _permutations(remainder)) {
      yield [values[index], ...rest];
    }
  }
}
