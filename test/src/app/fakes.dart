import 'package:did_i_assist/src/domain/location/geofence_registrar.dart';
import 'package:did_i_assist/src/domain/location/geofence_registration_id.dart';
import 'package:did_i_assist/src/domain/location/location_permission_gateway.dart';
import 'package:did_i_assist/src/domain/location/position_fix.dart';
import 'package:did_i_assist/src/domain/location/position_provider.dart';
import 'package:did_i_assist/src/domain/models/place.dart';
import 'package:did_i_assist/src/domain/models/planned_notification.dart';
import 'package:did_i_assist/src/domain/repositories/class_sample_task_gateway.dart';
import 'package:did_i_assist/src/domain/repositories/notification_gateway.dart';
import 'package:did_i_assist/src/domain/services/class_sample_planner.dart';

final class FakeGeofenceRegistrar implements GeofenceRegistrar {
  final ids = <String>{};
  int reads = 0;
  bool failSync = false;
  @override
  Future<Set<String>> registeredIds() async {
    reads++;
    if (failSync) throw StateError('native registration failed');
    return {...ids};
  }

  @override
  Future<void> register(Place place) async =>
      ids.add(GeofenceRegistrationId.forPlace(place));
  @override
  Future<void> unregister(String registrationId) async =>
      ids.remove(registrationId);
}

final class FakePositionProvider implements PositionProvider {
  FakePositionProvider(this.fix);
  final PositionFix fix;
  int requests = 0;
  @override
  Future<PositionFix> currentFix({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    requests++;
    return fix;
  }

  @override
  Future<PositionFix?> lastKnownFix() async => fix;
}

final class FakePermissions implements LocationPermissionGateway {
  FakePermissions([this.status = LocationPermissionStatus.always]);

  LocationPermissionStatus status;
  @override
  Future<LocationPermissionStatus> check() async => status;
  @override
  Future<LocationPermissionStatus> requestForeground() => check();
  @override
  Future<LocationPermissionStatus> requestBackground() => check();
  @override
  Future<bool> openSettings({bool locationServices = false}) async => true;
}

final class FakeNotifications implements NotificationGateway {
  NotificationPermission permission = NotificationPermission.granted;
  Error? permissionError;
  Error? showError;
  Error? pendingError;
  final shown = <PlannedNotification>[];
  final scheduled = <PlannedNotification>[];
  final pending = <int, PlannedNotification>{};
  final canceled = <int>[];
  int permissionChecks = 0;
  int permissionRequests = 0;

  @override
  Future<NotificationPermission> ensurePermission() async {
    permissionChecks++;
    if (permissionError case final error?) throw error;
    return permission;
  }

  @override
  Future<NotificationPermission> requestPermission() async {
    permissionRequests++;
    return permission;
  }

  @override
  Future<void> show(PlannedNotification notification) async {
    if (showError case final error?) throw error;
    shown.add(notification);
  }

  @override
  Future<void> schedule(PlannedNotification notification) async {
    scheduled.add(notification);
    pending[notification.id] = notification;
  }

  @override
  Future<List<PlannedNotification>> pendingNotifications() async {
    if (pendingError case final error?) throw error;
    return pending.values.toList();
  }

  @override
  Future<Set<int>> pendingIds() async => pending.keys.toSet();

  @override
  Future<void> cancel(int id) async {
    canceled.add(id);
    pending.remove(id);
  }

  @override
  Future<int> cancelWhere(bool Function(PlannedNotification) predicate) async {
    final matching = pending.values.where(predicate).toList();
    for (final notification in matching) {
      await cancel(notification.id);
    }
    return matching.length;
  }
}

final class FakeClassSampleGateway implements ClassSampleTaskGateway {
  final tasks = <String, ClassSampleTask>{};
  final decisions = <(String, ClassSampleSchedulePolicy)>[];
  final canceled = <String>[];
  bool failScheduling = false;
  @override
  Future<void> schedule(
    ClassSampleTask task,
    ClassSampleSchedulePolicy policy,
  ) async {
    if (failScheduling) throw StateError('native scheduling failed');
    decisions.add((task.uniqueName, policy));
    if (policy == ClassSampleSchedulePolicy.replace ||
        !tasks.containsKey(task.uniqueName)) {
      tasks[task.uniqueName] = task;
    }
  }

  @override
  Future<void> cancel(String uniqueName) async {
    canceled.add(uniqueName);
    tasks.remove(uniqueName);
  }
}
