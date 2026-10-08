import 'package:did_i_attend/src/core/geo_point.dart';
import 'package:did_i_attend/src/data/database/app_database.dart';
import 'package:did_i_attend/src/domain/models/place.dart';
import 'package:did_i_attend/src/domain/models/place_kind.dart';

Place placeFromRow(PlaceRow row) => Place(
  id: row.id,
  name: row.name,
  kind: PlaceKind.values.byName(row.kind),
  center: GeoPoint(latitude: row.latitude, longitude: row.longitude),
  radiusMeters: row.radiusMeters,
);

PlacesCompanion placeToCompanion(Place place) => PlacesCompanion.insert(
  id: place.id,
  name: place.name,
  kind: place.kind.name,
  latitude: place.center.latitude,
  longitude: place.center.longitude,
  radiusMeters: place.radiusMeters,
);
