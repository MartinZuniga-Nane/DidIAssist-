import 'package:did_i_attend/src/domain/location/location_permission_gateway.dart';
import 'package:did_i_attend/src/domain/repositories/notification_gateway.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

enum PermissionStep {
  locationServices,
  foregroundLocation,
  backgroundLocation,
  activateLocation,
  notifications,
}

enum PermissionOutcome {
  ready,
  denied,
  needsSettings,
  unavailable,
  failed,
}

@immutable
final class PermissionState extends Equatable {
  const PermissionState({required this.location, required this.notifications});

  final LocationPermissionStatus location;
  final NotificationPermission notifications;

  @override
  List<Object> get props => [location, notifications];
}

@immutable
final class PermissionRequestResult extends Equatable {
  const PermissionRequestResult({
    required this.outcome,
    this.blockedAt,
    this.location,
    this.notifications,
    this.error,
  });

  final PermissionOutcome outcome;
  final PermissionStep? blockedAt;
  final LocationPermissionStatus? location;
  final NotificationPermission? notifications;
  final Object? error;

  @override
  List<Object?> get props => [
    outcome,
    blockedAt,
    location,
    notifications,
    error,
  ];
}

final class PermissionOnboarding {
  PermissionOnboarding({
    required LocationPermissionGateway location,
    required NotificationGateway notifications,
    required Future<void> Function() syncGeofences,
    required Future<void> Function() syncClassSamples,
  }) : _location = location,
       _notifications = notifications,
       _syncGeofences = syncGeofences,
       _syncClassSamples = syncClassSamples;

  final LocationPermissionGateway _location;
  final NotificationGateway _notifications;
  final Future<void> Function() _syncGeofences;
  final Future<void> Function() _syncClassSamples;
  Future<PermissionRequestResult>? _requesting;

  Future<PermissionState> currentState() async => PermissionState(
    location: await _location.check(),
    notifications: await _notifications.ensurePermission(),
  );

  Future<PermissionRequestResult> request() async {
    final requesting = _requesting ??= _request();
    try {
      return await requesting;
    } finally {
      if (identical(_requesting, requesting)) _requesting = null;
    }
  }

  Future<PermissionRequestResult> _request() async {
    var step = PermissionStep.foregroundLocation;
    LocationPermissionStatus? location;
    NotificationPermission? notifications;
    PermissionRequestResult blocked(
      PermissionOutcome outcome,
      PermissionStep at,
    ) => PermissionRequestResult(
      outcome: outcome,
      blockedAt: at,
      location: location,
      notifications: notifications,
    );
    PermissionRequestResult? locationBlock(PermissionStep at) =>
        switch (location) {
          LocationPermissionStatus.serviceDisabled => blocked(
            PermissionOutcome.needsSettings,
            PermissionStep.locationServices,
          ),
          LocationPermissionStatus.deniedForever => blocked(
            PermissionOutcome.needsSettings,
            at,
          ),
          LocationPermissionStatus.denied => blocked(
            PermissionOutcome.denied,
            at,
          ),
          _ => null,
        };
    try {
      location = await _location.check();
      if (location == LocationPermissionStatus.serviceDisabled ||
          location == LocationPermissionStatus.deniedForever) {
        return locationBlock(step)!;
      }
      if (location == LocationPermissionStatus.denied) {
        location = await _location.requestForeground();
        if (locationBlock(step) case final blocked?) return blocked;
      }
      if (location == LocationPermissionStatus.whileInUse) {
        step = PermissionStep.backgroundLocation;
        location = await _location.requestBackground();
        if (locationBlock(step) case final blocked?) return blocked;
        if (location != LocationPermissionStatus.always) {
          return blocked(PermissionOutcome.needsSettings, step);
        }
      }
      step = PermissionStep.activateLocation;
      Object? activationError;
      for (final sync in [_syncGeofences, _syncClassSamples]) {
        try {
          await sync();
        } on Object catch (error) {
          activationError ??= error;
        }
      }
      if (activationError != null) {
        return PermissionRequestResult(
          outcome: PermissionOutcome.failed,
          blockedAt: step,
          location: location,
          error: activationError,
        );
      }
      step = PermissionStep.notifications;
      notifications = await _notifications.ensurePermission();
      if (notifications == NotificationPermission.denied) {
        notifications = await _notifications.requestPermission();
      }
      return switch (notifications) {
        NotificationPermission.granted => PermissionRequestResult(
          outcome: PermissionOutcome.ready,
          location: location,
          notifications: notifications,
        ),
        NotificationPermission.denied => blocked(
          PermissionOutcome.denied,
          step,
        ),
        NotificationPermission.unavailable => blocked(
          PermissionOutcome.unavailable,
          step,
        ),
      };
    } on Object catch (error) {
      return PermissionRequestResult(
        outcome: PermissionOutcome.failed,
        blockedAt: step,
        location: location,
        notifications: notifications,
        error: error,
      );
    }
  }
}
