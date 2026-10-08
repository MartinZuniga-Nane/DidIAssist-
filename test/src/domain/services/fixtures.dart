import 'package:did_i_attend/src/core/geo_point.dart';
import 'package:did_i_attend/src/domain/models/models.dart';

GeoPoint eiffelTower() => GeoPoint(latitude: 48.8584, longitude: 2.2945);
GeoPoint louvre() => GeoPoint(latitude: 48.8606, longitude: 2.3376);
GeoPoint arcDeTriomphe() => GeoPoint(latitude: 48.8738, longitude: 2.295);
GeoPoint bigBen() => GeoPoint(latitude: 51.5007, longitude: -0.1246);

Place homePlace({String id = 'home'}) => Place(
  id: id,
  name: 'Home',
  kind: PlaceKind.home,
  center: eiffelTower(),
);

Place campusPlace({String id = 'campus'}) => Place(
  id: id,
  name: 'Campus',
  kind: PlaceKind.campus,
  center: louvre(),
);

ClassOccurrence occurrence({DateTime? start, Place? place}) {
  final destination = place ?? campusPlace();
  final classStart = start ?? DateTime(2026, 10, 5, 9);
  final course = Course(id: 'course', name: 'Mathematics');
  final slot = ScheduleSlot(
    id: 'slot',
    courseId: course.id,
    placeId: destination.id,
    weekday: classStart.weekday,
    startMinute: classStart.hour * 60 + classStart.minute,
    durationMinutes: 90,
  );
  return ClassOccurrence(
    slot: slot,
    course: course,
    place: destination,
    start: classStart,
    end: classStart.add(const Duration(minutes: 90)),
  );
}

LocationEvent transition(
  LocationEventType type,
  DateTime time, {
  String placeId = 'home',
  String? id,
}) => LocationEvent(
  id: id ?? '$placeId-${type.name}-${time.microsecondsSinceEpoch}',
  type: type,
  placeId: placeId,
  recordedAt: time,
);

Trip commute({
  required Duration duration,
  String id = 'trip',
  String fromPlaceId = 'home',
  String toPlaceId = 'campus',
  DateTime? arrivedAt,
}) {
  final arrival = arrivedAt ?? DateTime(2026, 10, 5, 9);
  return Trip(
    id: id,
    fromPlaceId: fromPlaceId,
    toPlaceId: toPlaceId,
    departedAt: arrival.subtract(duration),
    arrivedAt: arrival,
  );
}
