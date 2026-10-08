import 'package:clock/clock.dart';
import 'package:did_i_attend/src/domain/location/background_location_handler.dart';
import 'package:did_i_attend/src/platform/native_geofence_mapper.dart';
import 'package:native_geofence/native_geofence.dart';

/// Registration is isolate-local. Background bootstrap must register a handler
/// in its own isolate; registration in the UI isolate does not cross isolates.
abstract final class BackgroundLocationRegistry {
  static BackgroundLocationHandler? _handler;
  static Clock? _timeSource;

  static bool get isRegistered => _handler != null;

  static void register(BackgroundLocationHandler handler, {Clock? timeSource}) {
    _handler = handler;
    _timeSource = timeSource;
  }

  static void clear() {
    _handler = null;
    _timeSource = null;
  }
}

@pragma('vm:entry-point')
Future<void> nativeGeofenceCallback(GeofenceCallbackParams params) async {
  final receivedAt = (BackgroundLocationRegistry._timeSource ?? clock).now();
  final transition = const NativeGeofenceMapper().map(
    params,
    receivedAt: receivedAt,
  );
  if (transition == null) return;
  final handler = BackgroundLocationRegistry._handler;
  if (handler == null) {
    throw StateError(
      'Background location handler is not registered in this isolate.',
    );
  }
  await handler.handle(transition);
}
