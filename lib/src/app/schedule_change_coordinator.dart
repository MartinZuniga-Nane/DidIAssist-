import 'dart:async';

import 'package:did_i_attend/src/domain/repositories/course_repository.dart';
import 'package:did_i_attend/src/domain/repositories/place_repository.dart';
import 'package:did_i_attend/src/domain/repositories/settings_repository.dart';

final class ScheduleChangeCoordinator {
  ScheduleChangeCoordinator({
    required PlaceRepository places,
    required CourseRepository courses,
    required SettingsRepository settings,
    required Future<void> Function() syncGeofences,
    required Future<void> Function() syncClassSamples,
    required Future<void> Function() reconcileReminders,
    required void Function(Object, StackTrace) onError,
    Duration debounce = const Duration(milliseconds: 250),
    Timer Function(Duration, void Function()) createTimer = Timer.new,
  }) : _places = places,
       _courses = courses,
       _settings = settings,
       _syncGeofences = syncGeofences,
       _syncClassSamples = syncClassSamples,
       _reconcileReminders = reconcileReminders,
       _onError = onError,
       _debounce = debounce,
       _createTimer = createTimer {
    if (debounce.isNegative) {
      throw ArgumentError.value(debounce, 'debounce', 'Must be nonnegative.');
    }
  }

  final PlaceRepository _places;
  final CourseRepository _courses;
  final SettingsRepository _settings;
  final Future<void> Function() _syncGeofences;
  final Future<void> Function() _syncClassSamples;
  final Future<void> Function() _reconcileReminders;
  final void Function(Object, StackTrace) _onError;
  final Duration _debounce;
  final Timer Function(Duration, void Function()) _createTimer;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  Timer? _timer;
  Future<void>? _running;
  Future<void>? _closing;
  bool _started = false;
  bool _disposed = false;
  bool _dirty = false;
  bool _placesDirty = false;

  void start() {
    if (_disposed) throw StateError('Coordinator is disposed.');
    if (_started) return;
    _started = true;
    _subscriptions
      ..add(
        _places.watchAll().listen(
          (_) => _changed(placesChanged: true),
          onError: _onError,
        ),
      )
      ..add(
        _courses.watchAll().listen((_) => _changed(), onError: _onError),
      )
      ..add(
        _courses.watchSlots().listen((_) => _changed(), onError: _onError),
      )
      ..add(
        _settings.watch().listen((_) => _changed(), onError: _onError),
      );
  }

  void _changed({bool placesChanged = false}) {
    if (_disposed) return;
    _dirty = true;
    _placesDirty |= placesChanged;
    _timer?.cancel();
    _timer = _createTimer(_debounce, () => unawaited(flush()));
  }

  Future<void> flush() async {
    _timer?.cancel();
    while (_running != null) {
      await _running;
    }
    if (_disposed || !_dirty) return;
    final placesChanged = _placesDirty;
    _dirty = false;
    _placesDirty = false;
    final running = _run(placesChanged);
    _running = running;
    try {
      await running;
    } finally {
      _running = null;
    }
  }

  Future<void> _run(bool placesChanged) async {
    for (final action in [
      if (placesChanged) _syncGeofences,
      _syncClassSamples,
      _reconcileReminders,
    ]) {
      if (_disposed) return;
      try {
        await action();
      } on Object catch (error, stackTrace) {
        _onError(error, stackTrace);
      }
    }
  }

  Future<void> dispose() => _closing ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    _timer?.cancel();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _running;
  }
}
