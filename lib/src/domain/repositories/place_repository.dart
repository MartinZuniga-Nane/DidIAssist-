import 'package:did_i_attend/src/domain/models/place.dart';

abstract interface class PlaceRepository {
  Future<Place?> getById(String id);
  Future<List<Place>> getAll();
  Stream<List<Place>> watchAll();
  Future<void> save(Place place);
  Future<void> delete(String id);
}
