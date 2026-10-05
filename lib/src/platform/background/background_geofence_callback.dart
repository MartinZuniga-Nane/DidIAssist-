import 'package:did_i_assist/src/app/app_services.dart';
import 'package:did_i_assist/src/platform/background/open_background_services.dart';
import 'package:did_i_assist/src/platform/background_location_callback.dart';
import 'package:native_geofence/native_geofence.dart';

Future<void> _pending = Future<void>.value();

@pragma('vm:entry-point')
Future<void> backgroundGeofenceCallback(GeofenceCallbackParams params) =>
    dispatchBackgroundGeofence(params);

Future<void> dispatchBackgroundGeofence(
  GeofenceCallbackParams params, {
  Future<BackgroundTaskServices> Function() openServices =
      openBackgroundServices,
}) {
  // Registry registration is isolate-local and must live until delegation ends.
  // Serialize callbacks so another bootstrap cannot replace a live handler.
  final next = _pending.then((_) async {
    final services = await openServices();
    try {
      BackgroundLocationRegistry.register(
        services.pipeline,
        timeSource: services.timeSource,
      );
      await nativeGeofenceCallback(params);
    } finally {
      BackgroundLocationRegistry.clear();
      await services.dispose();
    }
  });
  _pending = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
  return next;
}
