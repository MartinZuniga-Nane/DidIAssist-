final class PlaceInUseException implements Exception {
  const PlaceInUseException(this.placeId);

  final String placeId;

  @override
  String toString() =>
      'PlaceInUseException: Place "$placeId" is referenced by schedule slots.';
}
