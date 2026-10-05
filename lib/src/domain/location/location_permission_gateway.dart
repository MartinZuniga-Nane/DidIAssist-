enum LocationPermissionStatus {
  serviceDisabled,
  denied,
  deniedForever,
  whileInUse,
  always,
}

abstract interface class LocationPermissionGateway {
  Future<LocationPermissionStatus> check();
  Future<LocationPermissionStatus> requestForeground();
  Future<LocationPermissionStatus> requestBackground();
  Future<bool> openSettings({bool locationServices = false});
}
