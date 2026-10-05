import 'package:did_i_assist/src/domain/models/models.dart';
import 'package:did_i_assist/src/domain/models/planned_notification.dart';
import 'package:did_i_assist/src/domain/services/departure_advisor.dart';
import 'package:did_i_assist/src/domain/services/eta_estimator.dart';
import 'package:did_i_assist/src/domain/services/notification_id.dart';
import 'package:did_i_assist/src/domain/services/reminder_planner.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  final now = DateTime(2026, 10, 5, 8);
  const planner = ReminderPlanner();
  final classOccurrence = occurrence();
  DepartureAdvice advice({
    DepartureStatus status = DepartureStatus.onTime,
    DateTime? leaveBy,
    Duration eta = const Duration(minutes: 20),
  }) => DepartureAdvice(
    status: status,
    eta: EtaEstimate(duration: eta, source: EtaSource.heuristic, sampleSize: 0),
    expectedArrival: now.add(eta),
    leaveBy: leaveBy ?? now.add(const Duration(minutes: 35)),
    lateBy: status == DepartureStatus.late
        ? const Duration(minutes: 2)
        : Duration.zero,
    originKind: OriginKind.home,
  );
  List<PlannedNotification> plan({
    Map<ClassOccurrence, DepartureAdvice>? departures,
    UserSettings? settings,
  }) => planner.plan(
    departures: departures ?? {classOccurrence: advice()},
    settings: settings ?? UserSettings(),
    now: now,
  );

  for (final status in DepartureStatus.values) {
    test('plans only onTime advice: ${status.name}', () {
      final result = plan(
        departures: {classOccurrence: advice(status: status)},
      );
      expect(result.length, status == DepartureStatus.onTime ? 1 : 0);
    });
  }

  for (final offset in [-1, 0, 1]) {
    test('leaveBy must be strictly future: $offset microseconds', () {
      final result = plan(
        departures: {
          classOccurrence: advice(
            leaveBy: now.add(Duration(microseconds: offset)),
          ),
        },
      );
      expect(result.length, offset > 0 ? 1 : 0);
    });
  }

  test('disabled notifications produce no reminders', () {
    expect(plan(settings: UserSettings(notificationsEnabled: false)), isEmpty);
  });

  test('empty input produces no reminders', () {
    expect(plan(departures: {}), isEmpty);
  });

  test('stores structural metadata and rounds ETA up', () {
    final result = plan(
      departures: {
        classOccurrence: advice(eta: const Duration(minutes: 20, seconds: 1)),
      },
    ).single;
    expect(result.kind, NotificationKind.departureReminder);
    expect(result.at, advice().leaveBy.toUtc());
    expect(
      result.id,
      notificationId(
        kind: NotificationKind.departureReminder,
        slotId: classOccurrence.slot.id,
        occurrenceDate: classOccurrence.occurrenceDate,
      ),
    );
    expect(result.payload['courseName'], 'Mathematics');
    expect(result.payload['placeName'], 'Campus');
    expect(result.payload['etaMinutes'], '21');
  });

  test('multiple classes are sorted by leaveBy then deterministic ID', () {
    final second = occurrence(start: DateTime(2026, 10, 6, 9));
    final third = occurrence(start: DateTime(2026, 10, 7, 9));
    final result = plan(
      departures: {
        third: advice(),
        classOccurrence: advice(
          leaveBy: now.add(const Duration(minutes: 10)),
        ),
        second: advice(),
      },
    );
    expect(result, hasLength(3));
    expect(result.first.payload['occurrenceDate'], '2026-10-05');
    expect(result[1].id, lessThan(result[2].id));
    expect(result.clear, throwsUnsupportedError);
  });

  test(
    'an already-started class is not scheduled even with future leaveBy',
    () {
      expect(plan(departures: {occurrence(start: now): advice()}), isEmpty);
    },
  );
}
