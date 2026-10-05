import 'package:did_i_assist/src/domain/models/model_validation.dart';
import 'package:did_i_assist/src/domain/models/trip.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

@immutable
final class CommuteStats extends Equatable {
  CommuteStats({required this.medianDuration, required this.sampleSize}) {
    requireNonNegative(medianDuration.inMicroseconds, 'medianDuration');
    requireNonNegative(sampleSize, 'sampleSize');
  }

  final Duration medianDuration;
  final int sampleSize;

  @override
  List<Object> get props => [medianDuration, sampleSize];
}

final class CommuteLearner {
  const CommuteLearner();

  CommuteStats learn({
    required Iterable<Trip> trips,
    required String fromPlaceId,
    required String toPlaceId,
  }) {
    final valid =
        trips
            .where(
              (trip) =>
                  trip.fromPlaceId == fromPlaceId &&
                  trip.toPlaceId == toPlaceId &&
                  trip.duration >= const Duration(minutes: 3) &&
                  trip.duration <= const Duration(minutes: 180),
            )
            .toList()
          ..sort((a, b) {
            final arrivalOrder = b.arrivedAt.compareTo(a.arrivedAt);
            return arrivalOrder != 0 ? arrivalOrder : a.id.compareTo(b.id);
          });
    final durations = valid.take(10).map((trip) => trip.duration).toList()
      ..sort();
    if (durations.isEmpty) {
      return CommuteStats(medianDuration: Duration.zero, sampleSize: 0);
    }
    final middle = durations.length ~/ 2;
    final median = durations.length.isOdd
        ? durations[middle]
        : Duration(
            seconds:
                ((durations[middle - 1].inMicroseconds +
                            durations[middle].inMicroseconds) /
                        (2 * Duration.microsecondsPerSecond))
                    .round(),
          );
    return CommuteStats(medianDuration: median, sampleSize: durations.length);
  }
}
