import 'package:did_i_assist/src/domain/location/geofence_registrar.dart';
import 'package:did_i_assist/src/domain/location/geofence_registration_id.dart';
import 'package:did_i_assist/src/domain/location/location_permission_gateway.dart';
import 'package:did_i_assist/src/domain/location/position_fix.dart';
import 'package:did_i_assist/src/domain/location/position_provider.dart';
import 'package:did_i_assist/src/domain/models/place.dart';
import 'package:did_i_assist/src/domain/repositories/class_sample_task_gateway.dart';
import 'package:did_i_assist/src/domain/services/class_sample_planner.dart';

final class FakeGeofenceRegistrar implements GeofenceRegistrar {
  final ids = <String>{};
  int reads = 0;
  @override
  Future<Set<String>> registeredIds() async {
    reads++;
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
  @override
  Future<LocationPermissionStatus> check() async =>
      LocationPermissionStatus.always;
  @override
  Future<LocationPermissionStatus> requestForeground() => check();
  @override
  Future<LocationPermissionStatus> requestBackground() => check();
  @override
  Future<bool> openSettings({bool locationServices = false}) async => true;
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
