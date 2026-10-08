import 'package:flutter/foundation.dart';

void reportAppError(Object error, StackTrace stackTrace) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
      library: 'DidIAttend startup',
    ),
  );
}
