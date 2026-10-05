import 'dart:async';

import 'package:did_i_assist/src/domain/location/position_fix.dart';
import 'package:did_i_assist/src/domain/location/position_provider.dart';
import 'package:did_i_assist/src/domain/models/location_event.dart';
import 'package:did_i_assist/src/domain/models/location_event_type.dart';
import 'package:did_i_assist/src/domain/services/location_event_recorder.dart';
import 'package:did_i_assist/src/domain/services/position_sampler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../location/mocks.dart';
import 'fixtures.dart';

void main() {
  final fix = PositionFix(
    position: eiffelTower(),
    accuracyMeters: 10,
    timestamp: DateTime.utc(2026, 10, 5, 9),
  );
  late MockPositionProvider provider;
  late MockLocationEventRepository repository;
  late PositionSampler sampler;

  setUpAll(() {
    registerFallbackValue(Duration.zero);
    registerFallbackValue(
      LocationEvent(
        id: 'fallback',
        type: LocationEventType.positionSample,
        position: fix.position,
        recordedAt: fix.timestamp,
      ),
    );
  });
  setUp(() {
    provider = MockPositionProvider();
    repository = MockLocationEventRepository();
    when(
      () => provider.currentFix(timeout: any(named: 'timeout')),
    ).thenAnswer((_) async => fix);
    when(() => repository.append(any())).thenAnswer((_) async {});
    sampler = PositionSampler(
      positionProvider: provider,
      recorder: LocationEventRecorder(
        repository: repository,
        generateId: () => 'sample',
      ),
    );
  });

  test('takes a current fix and records a position sample', () async {
    final result = await sampler.sample();
    expect(result, isA<PositionSampleRecorded>());
    final event = (result as PositionSampleRecorded).event;
    expect(event.position, fix.position);
    expect(event.recordedAt, fix.timestamp);
    expect(event.accuracyMeters, 10);
    verify(() => provider.currentFix()).called(1);
    verify(() => repository.append(event)).called(1);
    expect(result, PositionSampleRecorded(event));
  });

  for (final reason in PositionFailureReason.values) {
    test('returns typed $reason without writing any event', () async {
      when(
        () => provider.currentFix(timeout: any(named: 'timeout')),
      ).thenThrow(PositionUnavailable(reason));
      expect(await sampler.sample(), PositionSampleFailed(reason));
      verifyNever(() => repository.append(any()));
    });
  }

  test('handles a Dart timeout and forwards the requested timeout', () async {
    when(
      () => provider.currentFix(timeout: any(named: 'timeout')),
    ).thenThrow(TimeoutException('no fix'));
    expect(
      await sampler.sample(timeout: const Duration(seconds: 5)),
      const PositionSampleFailed(PositionFailureReason.timeout),
    );
    verify(
      () => provider.currentFix(timeout: const Duration(seconds: 5)),
    ).called(1);
  });

  test('enforces timeout if a provider never completes', () async {
    when(
      () => provider.currentFix(timeout: any(named: 'timeout')),
    ).thenAnswer((_) => Completer<PositionFix>().future);
    expect(
      await sampler.sample(timeout: const Duration(milliseconds: 1)),
      const PositionSampleFailed(PositionFailureReason.timeout),
    );
    verifyNever(() => repository.append(any()));
  });

  test('persistence timeouts are not swallowed as location timeouts', () async {
    when(() => repository.append(any())).thenThrow(TimeoutException('storage'));
    await expectLater(sampler.sample(), throwsA(isA<TimeoutException>()));
  });

  test('unexpected provider failures propagate', () async {
    when(
      () => provider.currentFix(timeout: any(named: 'timeout')),
    ).thenThrow(StateError('unexpected'));
    await expectLater(sampler.sample(), throwsStateError);
  });

  test('rejects nonpositive timeout before accessing the provider', () async {
    for (final timeout in [Duration.zero, const Duration(seconds: -1)]) {
      await expectLater(sampler.sample(timeout: timeout), throwsArgumentError);
    }
    verifyNever(() => provider.currentFix(timeout: any(named: 'timeout')));
  });
}
