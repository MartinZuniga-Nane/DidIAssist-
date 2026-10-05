import 'dart:convert';
import 'dart:typed_data';

import 'package:did_i_assist/src/domain/models/place.dart';

/// Stores ownership and geometry in the OS ID, surviving process restarts.
abstract final class GeofenceRegistrationId {
  static const _prefix = 'didiassist:v1:';

  static String forPlace(Place place) {
    final geometry = ByteData(24)
      ..setFloat64(0, place.center.latitude)
      ..setFloat64(8, place.center.longitude)
      ..setFloat64(16, place.radiusMeters);
    final fingerprint = base64Url.encode(geometry.buffer.asUint8List());
    return '$_prefix${Uri.encodeComponent(place.id)}:$fingerprint';
  }

  static String? placeIdFrom(String registrationId) {
    if (!registrationId.startsWith(_prefix)) return null;
    final parts = registrationId.substring(_prefix.length).split(':');
    if (parts.length != 2) return null;
    final encodedPlaceId = parts[0];
    if (encodedPlaceId.codeUnits.any((unit) => unit > 127) ||
        RegExp('%(?![0-9a-fA-F]{2})').hasMatch(encodedPlaceId)) {
      return null;
    }
    try {
      final placeId = Uri.decodeComponent(encodedPlaceId);
      if (placeId.trim().isEmpty) return null;
      final bytes = base64Url.decode(parts[1]);
      if (bytes.length != 24) return null;
      final geometry = ByteData.sublistView(bytes);
      final latitude = geometry.getFloat64(0);
      final longitude = geometry.getFloat64(8);
      final radius = geometry.getFloat64(16);
      if (!latitude.isFinite ||
          latitude < -90 ||
          latitude > 90 ||
          !longitude.isFinite ||
          longitude < -180 ||
          longitude > 180) {
        return null;
      }
      if (!radius.isFinite || radius < 100 || radius > 1000) return null;
      return placeId;
    } on FormatException {
      return null;
    }
  }
}
