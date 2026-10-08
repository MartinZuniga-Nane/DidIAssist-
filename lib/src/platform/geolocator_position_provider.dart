import 'dart:async';

import 'package:did_i_attend/src/core/geo_point.dart';
import 'package:did_i_attend/src/domain/location/position_fix.dart';
import 'package:did_i_attend/src/domain/location/position_provider.dart';
import 'package:geolocator/geolocator.dart' as geo;

final class GeolocatorPositionProvider implements PositionProvider {
  GeolocatorPositionProvider({geo.GeolocatorPlatform? platform})
    : _platform = platform ?? geo.GeolocatorPlatform.instance;

  final geo.GeolocatorPlatform _platform;

  @override
  Future<PositionFix> currentFix({
    Duration timeout = const Duration(seconds: 30),
  }) {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'Must be positive.');
    }
    return _translate(() async {
      if (!await _platform.isLocationServiceEnabled()) {
        throw const PositionUnavailable(PositionFailureReason.serviceDisabled);
      }
      final permission = await _platform.checkPermission();
      if (permission != geo.LocationPermission.whileInUse &&
          permission != geo.LocationPermission.always) {
        throw const PositionUnavailable(PositionFailureReason.permissionDenied);
      }
      final position = await _platform
          .getCurrentPosition(
            locationSettings: geo.LocationSettings(
              accuracy: geo.LocationAccuracy.high,
              timeLimit: timeout,
            ),
          )
          .timeout(timeout);
      return _fromPosition(position);
    });
  }

  @override
  Future<PositionFix?> lastKnownFix() => _translate(() async {
    final position = await _platform.getLastKnownPosition();
    return position == null ? null : _fromPosition(position);
  });

  static PositionFix _fromPosition(geo.Position position) => PositionFix(
    position: GeoPoint(
      latitude: position.latitude,
      longitude: position.longitude,
    ),
    accuracyMeters: position.accuracy.isFinite && position.accuracy >= 0
        ? position.accuracy
        : null,
    timestamp: position.timestamp,
  );

  static Future<T> _translate<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on TimeoutException {
      throw const PositionUnavailable(PositionFailureReason.timeout);
    } on geo.PermissionDeniedException {
      throw const PositionUnavailable(PositionFailureReason.permissionDenied);
    } on geo.LocationServiceDisabledException {
      throw const PositionUnavailable(PositionFailureReason.serviceDisabled);
    }
  }
}
