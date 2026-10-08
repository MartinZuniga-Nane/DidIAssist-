import 'dart:async';

import 'package:did_i_attend/src/app/permission_onboarding.dart';
import 'package:did_i_attend/src/domain/location/location_permission_gateway.dart';
import 'package:did_i_attend/src/domain/repositories/notification_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

final class _Location extends Mock implements LocationPermissionGateway {}

final class _Notifications extends Mock implements NotificationGateway {}

void main() {
  late _Location location;
  late _Notifications notifications;
  late PermissionOnboarding onboarding;
  late LocationPermissionStatus status;
  late LocationPermissionStatus foreground;
  late LocationPermissionStatus background;
  late NotificationPermission notificationStatus;
  late NotificationPermission requestedNotification;
  late List<String> calls;
  late Error? geofenceError;
  late Error? sampleError;

  setUp(() {
    location = _Location();
    notifications = _Notifications();
    status = LocationPermissionStatus.denied;
    foreground = LocationPermissionStatus.whileInUse;
    background = LocationPermissionStatus.always;
    notificationStatus = NotificationPermission.denied;
    requestedNotification = NotificationPermission.granted;
    calls = [];
    geofenceError = null;
    sampleError = null;
    when(location.check).thenAnswer((_) async {
      calls.add('location.check');
      return status;
    });
    when(location.requestForeground).thenAnswer((_) async {
      calls.add('foreground');
      return status = foreground;
    });
    when(location.requestBackground).thenAnswer((_) async {
      calls.add('background');
      return status = background;
    });
    when(notifications.ensurePermission).thenAnswer((_) async {
      calls.add('notifications.check');
      return notificationStatus;
    });
    when(notifications.requestPermission).thenAnswer((_) async {
      calls.add('notifications.request');
      return requestedNotification;
    });
    onboarding = PermissionOnboarding(
      location: location,
      notifications: notifications,
      syncGeofences: () async {
        calls.add('geofences');
        if (geofenceError case final error?) throw error;
      },
      syncClassSamples: () async {
        calls.add('samples');
        if (sampleError case final error?) throw error;
      },
    );
  });

  for (final locationState in LocationPermissionStatus.values) {
    for (final notificationState in NotificationPermission.values) {
      test(
        'reports $locationState and $notificationState without prompts',
        () async {
          status = locationState;
          notificationStatus = notificationState;
          expect(
            await onboarding.currentState(),
            PermissionState(
              location: locationState,
              notifications: notificationState,
            ),
          );
          expect(calls, ['location.check', 'notifications.check']);
        },
      );
    }
  }

  for (final initial in LocationPermissionStatus.values) {
    test('request sequence from ${initial.name}', () async {
      status = initial;
      final result = await onboarding.request();
      if (initial == LocationPermissionStatus.serviceDisabled ||
          initial == LocationPermissionStatus.deniedForever) {
        expect(result.outcome, PermissionOutcome.needsSettings);
        expect(
          result.blockedAt,
          initial == LocationPermissionStatus.serviceDisabled
              ? PermissionStep.locationServices
              : PermissionStep.foregroundLocation,
        );
        expect(calls, ['location.check']);
      } else {
        expect(result.outcome, PermissionOutcome.ready);
        expect(calls, [
          'location.check',
          if (initial == LocationPermissionStatus.denied) 'foreground',
          if (initial != LocationPermissionStatus.always) 'background',
          'geofences',
          'samples',
          'notifications.check',
          'notifications.request',
        ]);
      }
    });
  }

  for (final returned in LocationPermissionStatus.values) {
    test('foreground platform outcome ${returned.name}', () async {
      foreground = returned;
      final result = await onboarding.request();
      if (returned == LocationPermissionStatus.always ||
          returned == LocationPermissionStatus.whileInUse) {
        expect(result.outcome, PermissionOutcome.ready);
        expect(
          calls.contains('background'),
          returned == LocationPermissionStatus.whileInUse,
        );
      } else {
        expect(
          result.outcome,
          returned == LocationPermissionStatus.denied
              ? PermissionOutcome.denied
              : PermissionOutcome.needsSettings,
        );
        expect(calls, ['location.check', 'foreground']);
        expect(result.location, returned);
        expect(result.notifications, isNull);
      }
    });
  }

  for (final returned in LocationPermissionStatus.values) {
    test('background platform outcome ${returned.name}', () async {
      status = LocationPermissionStatus.whileInUse;
      background = returned;
      final result = await onboarding.request();
      expect(
        result.outcome,
        returned == LocationPermissionStatus.always
            ? PermissionOutcome.ready
            : returned == LocationPermissionStatus.denied
            ? PermissionOutcome.denied
            : PermissionOutcome.needsSettings,
      );
      if (returned != LocationPermissionStatus.always) {
        expect(calls, ['location.check', 'background']);
        expect(
          result.blockedAt,
          returned == LocationPermissionStatus.serviceDisabled
              ? PermissionStep.locationServices
              : PermissionStep.backgroundLocation,
        );
        expect(result.location, returned);
      }
    });
  }

  for (final initial in NotificationPermission.values) {
    test(
      'notification state ${initial.name} follows location activation',
      () async {
        status = LocationPermissionStatus.always;
        notificationStatus = initial;
        final result = await onboarding.request();
        expect(
          result.outcome,
          initial == NotificationPermission.unavailable
              ? PermissionOutcome.unavailable
              : PermissionOutcome.ready,
        );
        expect(calls, [
          'location.check',
          'geofences',
          'samples',
          'notifications.check',
          if (initial == NotificationPermission.denied) 'notifications.request',
        ]);
      },
    );
  }

  for (final returned in NotificationPermission.values) {
    test('notification request outcome ${returned.name}', () async {
      requestedNotification = returned;
      final result = await onboarding.request();
      expect(result.notifications, returned);
      expect(result.outcome, switch (returned) {
        NotificationPermission.granted => PermissionOutcome.ready,
        NotificationPermission.denied => PermissionOutcome.denied,
        NotificationPermission.unavailable => PermissionOutcome.unavailable,
      });
      expect(
        result.blockedAt,
        returned == NotificationPermission.granted
            ? null
            : PermissionStep.notifications,
      );
      expect(
        calls.indexOf('samples'),
        lessThan(calls.indexOf('notifications.request')),
      );
    });
  }

  for (final failure in [
    ('check', PermissionStep.foregroundLocation),
    ('foreground', PermissionStep.foregroundLocation),
    ('background', PermissionStep.backgroundLocation),
    ('notificationCheck', PermissionStep.notifications),
    ('notificationRequest', PermissionStep.notifications),
  ]) {
    test(
      'platform failure ${failure.$1} returns a typed blocking result',
      () async {
        final error = StateError('platform failed');
        switch (failure.$1) {
          case 'check':
            when(location.check).thenThrow(error);
          case 'foreground':
            when(location.requestForeground).thenThrow(error);
          case 'background':
            when(location.requestBackground).thenThrow(error);
          case 'notificationCheck':
            when(notifications.ensurePermission).thenThrow(error);
          case 'notificationRequest':
            when(notifications.requestPermission).thenThrow(error);
        }
        final result = await onboarding.request();
        expect(result.outcome, PermissionOutcome.failed);
        expect(result.blockedAt, failure.$2);
        expect(result.error, same(error));
      },
    );
  }

  for (final failingSync in ['geofences', 'samples']) {
    test(
      '$failingSync failure still attempts both location activations',
      () async {
        final error = StateError('activation failed');
        if (failingSync == 'geofences') {
          geofenceError = error;
        } else {
          sampleError = error;
        }
        final result = await onboarding.request();
        expect(result.outcome, PermissionOutcome.failed);
        expect(result.blockedAt, PermissionStep.activateLocation);
        expect(result.error, same(error));
        expect(calls, [
          'location.check',
          'foreground',
          'background',
          'geofences',
          'samples',
        ]);
      },
    );
  }

  test(
    'concurrent requests share prompts and a later request can retry',
    () async {
      final pending = Completer<LocationPermissionStatus>();
      when(location.requestForeground).thenAnswer((_) {
        calls.add('foreground');
        return pending.future;
      });
      final first = onboarding.request();
      final second = onboarding.request();
      pending.complete(LocationPermissionStatus.whileInUse);
      expect(await first, await second);
      expect(calls.where((call) => call == 'foreground'), hasLength(1));
      status = LocationPermissionStatus.always;
      calls.clear();
      await onboarding.request();
      expect(calls.where((call) => call == 'geofences'), hasLength(1));
    },
  );

  test('permission values use value equality', () {
    expect(
      const PermissionRequestResult(outcome: PermissionOutcome.ready),
      const PermissionRequestResult(outcome: PermissionOutcome.ready),
    );
    expect(
      const PermissionState(
        location: LocationPermissionStatus.always,
        notifications: NotificationPermission.granted,
      ).hashCode,
      const PermissionState(
        location: LocationPermissionStatus.always,
        notifications: NotificationPermission.granted,
      ).hashCode,
    );
  });
}
