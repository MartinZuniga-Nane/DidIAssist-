import 'package:did_i_assist/src/core/geo_point.dart';
import 'package:did_i_assist/src/core/local_date.dart';
import 'package:did_i_assist/src/domain/models/models.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_test/flutter_test.dart';

const placeId = '11111111-1111-4111-8111-111111111111';
const courseId = '22222222-2222-4222-8222-222222222222';
const slotId = '33333333-3333-4333-8333-333333333333';
const recordId = '44444444-4444-4444-8444-444444444444';
const homeId = '55555555-5555-4555-8555-555555555555';

GeoPoint samplePoint() => GeoPoint(latitude: 48.8584, longitude: 2.2945);

Place samplePlace() => Place(
  id: placeId,
  name: 'Campus',
  kind: PlaceKind.campus,
  center: samplePoint(),
);

Course sampleCourse() => Course(id: courseId, name: 'Mathematics');

ScheduleSlot sampleSlot() => ScheduleSlot(
  id: slotId,
  courseId: courseId,
  placeId: placeId,
  weekday: DateTime.monday,
  startMinute: 540,
  durationMinutes: 90,
);

LocationEvent sampleEvent() => LocationEvent(
  id: recordId,
  type: LocationEventType.geofenceEnter,
  placeId: placeId,
  position: samplePoint(),
  accuracyMeters: 20,
  recordedAt: DateTime.utc(2026, 10, 5, 9),
);

AttendanceRecord sampleAttendance() => AttendanceRecord(
  id: recordId,
  slotId: slotId,
  courseId: courseId,
  occurrenceDate: LocalDate(2026, 10, 5),
  status: AttendanceStatus.present,
  source: AttendanceSource.automatic,
  checkInAt: DateTime.utc(2026, 10, 5, 9),
  evaluatedAt: DateTime.utc(2026, 10, 5, 11),
);

Trip sampleTrip() => Trip(
  id: recordId,
  fromPlaceId: homeId,
  toPlaceId: placeId,
  departedAt: DateTime.utc(2026, 10, 5, 8),
  arrivedAt: DateTime.utc(2026, 10, 5, 8, 30),
  mode: TravelMode.transit,
);

ClassOccurrence sampleOccurrence() => ClassOccurrence.forDate(
  slot: sampleSlot(),
  course: sampleCourse(),
  place: samplePlace(),
  date: LocalDate(2026, 10, 5),
);

void expectValueEquality(
  Equatable original,
  Equatable equal,
  Iterable<Equatable> variants,
) {
  expect(original, equal);
  expect(original.hashCode, equal.hashCode);
  for (final variant in variants) {
    expect(variant, isNot(original));
  }
}
