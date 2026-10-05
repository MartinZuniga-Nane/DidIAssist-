import 'package:did_i_assist/src/data/database/app_database.dart';
import 'package:did_i_assist/src/data/database/mappers/date_mapping.dart';
import 'package:did_i_assist/src/domain/models/travel_mode.dart';
import 'package:did_i_assist/src/domain/models/trip.dart';
import 'package:drift/drift.dart';

Trip tripFromRow(TripRow row) => Trip(
  id: row.id,
  fromPlaceId: row.fromPlaceId,
  toPlaceId: row.toPlaceId,
  departedAt: instantFromMilliseconds(row.departedAt),
  arrivedAt: instantFromMilliseconds(row.arrivedAt),
  mode: row.mode == null ? null : TravelMode.values.byName(row.mode!),
);

TripsCompanion tripToCompanion(Trip trip) => TripsCompanion.insert(
  id: trip.id,
  fromPlaceId: trip.fromPlaceId,
  toPlaceId: trip.toPlaceId,
  departedAt: instantToMilliseconds(trip.departedAt),
  arrivedAt: instantToMilliseconds(trip.arrivedAt),
  mode: Value(trip.mode?.name),
);
