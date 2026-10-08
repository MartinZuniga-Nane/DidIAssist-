import 'package:clock/clock.dart';
import 'package:did_i_attend/src/domain/models/class_occurrence.dart';
import 'package:did_i_attend/src/domain/models/planned_notification.dart';
import 'package:did_i_attend/src/domain/repositories/course_repository.dart';
import 'package:did_i_attend/src/domain/repositories/notification_gateway.dart';
import 'package:did_i_attend/src/domain/repositories/place_repository.dart';
import 'package:did_i_attend/src/domain/repositories/settings_repository.dart';
import 'package:did_i_attend/src/domain/services/departure_advisor.dart';
import 'package:did_i_attend/src/domain/services/departure_service.dart';
import 'package:did_i_attend/src/domain/services/reminder_planner.dart';
import 'package:did_i_attend/src/domain/services/schedule_resolver.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

@immutable
final class ReminderSummary extends Equatable {
  ReminderSummary({
    required this.plannedCount,
    Iterable<int> scheduledIds = const [],
    Iterable<int> canceledIds = const [],
    Iterable<int> skippedIds = const [],
  }) : scheduledIds = List.unmodifiable(scheduledIds),
       canceledIds = List.unmodifiable(canceledIds),
       skippedIds = List.unmodifiable(skippedIds);

  final int plannedCount;
  final List<int> scheduledIds;
  final List<int> canceledIds;
  final List<int> skippedIds;

  @override
  List<Object> get props => [
    plannedCount,
    scheduledIds,
    canceledIds,
    skippedIds,
  ];
}

final class ReminderService {
  ReminderService({
    required CourseRepository courseRepository,
    required PlaceRepository placeRepository,
    required SettingsRepository settingsRepository,
    required DepartureService departureService,
    required NotificationGateway gateway,
    Clock? timeSource,
    ScheduleResolver resolver = const ScheduleResolver(),
    ReminderPlanner planner = const ReminderPlanner(),
  }) : _courses = courseRepository,
       _places = placeRepository,
       _settings = settingsRepository,
       _departures = departureService,
       _gateway = gateway,
       _clock = timeSource ?? clock,
       _resolver = resolver,
       _planner = planner;

  final CourseRepository _courses;
  final PlaceRepository _places;
  final SettingsRepository _settings;
  final DepartureService _departures;
  final NotificationGateway _gateway;
  final Clock _clock;
  final ScheduleResolver _resolver;
  final ReminderPlanner _planner;

  /// Reconciles class starts in the next 24 hours; the upper bound is excluded.
  Future<ReminderSummary> reconcile() async {
    final now = _clock.now();
    final settings = await _settings.load();
    final departures = <ClassOccurrence, DepartureAdvice>{};
    if (settings.notificationsEnabled) {
      final occurrences = _resolver.occurrencesBetween(
        from: now,
        until: now.add(const Duration(hours: 24)),
        courses: await _courses.getAll(),
        slots: await _courses.getSlots(),
        places: await _places.getAll(),
      );
      for (final occurrence in occurrences) {
        // Omitting currentPosition deliberately plans future trips from Home.
        final advice = await _departures.adviseFor(occurrence);
        if (advice != null) departures[occurrence] = advice;
      }
    }
    final planned = _planner.plan(
      departures: departures,
      settings: settings,
      now: now,
    );
    final plannedById = {for (final item in planned) item.id: item};
    final pending = await _gateway.pendingNotifications();
    final pendingById = {for (final item in pending) item.id: item};
    final occupiedIds = await _gateway.pendingIds();
    final canceled = <int>[];
    for (final item in pending) {
      if (item.kind == NotificationKind.departureReminder &&
          !plannedById.containsKey(item.id)) {
        await _gateway.cancel(item.id);
        canceled.add(item.id);
      }
    }
    final scheduled = <int>[];
    final skipped = <int>[];
    final permission = planned.isEmpty
        ? null
        : await _gateway.ensurePermission();
    for (final item in planned) {
      final previous = pendingById[item.id];
      if (previous == item) continue;
      if (permission != NotificationPermission.granted ||
          (occupiedIds.contains(item.id) &&
              previous?.kind != NotificationKind.departureReminder)) {
        skipped.add(item.id);
        continue;
      }
      await _gateway.schedule(item);
      scheduled.add(item.id);
    }
    return ReminderSummary(
      plannedCount: planned.length,
      scheduledIds: scheduled,
      canceledIds: canceled,
      skippedIds: skipped,
    );
  }
}
