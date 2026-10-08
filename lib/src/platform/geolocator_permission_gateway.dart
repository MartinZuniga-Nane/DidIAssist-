import 'package:did_i_attend/src/domain/location/location_permission_gateway.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:permission_handler/permission_handler.dart' as permissions;

final class GeolocatorPermissionGateway implements LocationPermissionGateway {
  GeolocatorPermissionGateway({
    geo.GeolocatorPlatform? platform,
    Future<permissions.PermissionStatus> Function()? requestAlways,
  }) : _platform = platform ?? geo.GeolocatorPlatform.instance,
       _requestAlways = requestAlways ?? _requestAlwaysPermission;

  final geo.GeolocatorPlatform _platform;
  final Future<permissions.PermissionStatus> Function() _requestAlways;

  static Future<permissions.PermissionStatus> _requestAlwaysPermission() =>
      permissions.Permission.locationAlways.request();

  @override
  Future<LocationPermissionStatus> check() async {
    if (!await _platform.isLocationServiceEnabled()) {
      return LocationPermissionStatus.serviceDisabled;
    }
    return _map(await _platform.checkPermission());
  }

  @override
  Future<LocationPermissionStatus> requestForeground() async {
    final status = await check();
    if (status != LocationPermissionStatus.denied) return status;
    return _map(await _platform.requestPermission());
  }

  @override
  Future<LocationPermissionStatus> requestBackground() async {
    final status = await requestForeground();
    if (status != LocationPermissionStatus.whileInUse) return status;
    // Geolocator's iOS request cannot upgrade an existing while-in-use grant.
    final background = await _requestAlways();
    if (background.isGranted) return LocationPermissionStatus.always;
    // Refusing background access does not revoke foreground access.
    return check();
  }

  @override
  Future<bool> openSettings({bool locationServices = false}) => locationServices
      ? _platform.openLocationSettings()
      : _platform.openAppSettings();

  static LocationPermissionStatus _map(
    geo.LocationPermission permission,
  ) => switch (permission) {
    geo.LocationPermission.denied => LocationPermissionStatus.denied,
    geo.LocationPermission.deniedForever =>
      LocationPermissionStatus.deniedForever,
    geo.LocationPermission.whileInUse => LocationPermissionStatus.whileInUse,
    geo.LocationPermission.always => LocationPermissionStatus.always,
    geo.LocationPermission.unableToDetermine => LocationPermissionStatus.denied,
  };
}
