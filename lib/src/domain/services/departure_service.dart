import 'package:clock/clock.dart';
import 'package:did_i_assist/src/core/geo_point.dart';
import 'package:did_i_assist/src/domain/models/class_occurrence.dart';
import 'package:did_i_assist/src/domain/models/place_kind.dart';
import 'package:did_i_assist/src/domain/models/trip.dart';
import 'package:did_i_assist/src/domain/repositories/place_repository.dart';
import 'package:did_i_assist/src/domain/repositories/settings_repository.dart';
import 'package:did_i_assist/src/domain/repositories/trip_repository.dart';
import 'package:did_i_assist/src/domain/services/commute_learner.dart';
import 'package:did_i_assist/src/domain/services/departure_advisor.dart';
import 'package:did_i_assist/src/domain/services/eta_estimator.dart';

final class DepartureService {
  DepartureService({
    required PlaceRepository placeRepository,
    required SettingsRepository settingsRepository,
    required TripRepository tripRepository,
    Clock? timeSource,
    EtaEstimator? estimator,
    CommuteLearner learner = const CommuteLearner(),
    DepartureAdvisor advisor = const DepartureAdvisor(),
  }) : _places = placeRepository,
       _settings = settingsRepository,
       _trips = tripRepository,
       _clock = timeSource ?? clock,
       _estimator = estimator ?? EtaEstimator(),
       _learner = learner,
       _advisor = advisor;

  final PlaceRepository _places;
  final SettingsRepository _settings;
  final TripRepository _trips;
  final Clock _clock;
  final EtaEstimator _estimator;
  final CommuteLearner _learner;
  final DepartureAdvisor _advisor;

  Future<DepartureAdvice?> adviseFor(
    ClassOccurrence occurrence, {
    GeoPoint? currentPosition,
  }) async {
    final places = await _places.getAll();
    final homes = places.where((place) => place.kind == PlaceKind.home).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final home = homes.isEmpty ? null : homes.first;
    final origin = currentPosition ?? home?.center;
    if (origin == null) return null;
    final settings = await _settings.load();
    final trips = home == null
        ? <Trip>[]
        : await _trips.getRecent(
            fromPlaceId: home.id,
            toPlaceId: occurrence.place.id,
          );
    final learned = home == null
        ? null
        : _learner.learn(
            trips: trips,
            fromPlaceId: home.id,
            toPlaceId: occurrence.place.id,
          );
    final eta = _estimator.estimate(
      origin: origin,
      destination: occurrence.place,
      mode: settings.defaultTravelMode,
      home: home,
      learned: learned,
    );
    return _advisor.advise(
      occurrence: occurrence,
      place: occurrence.place,
      origin: currentPosition,
      home: home,
      eta: eta,
      bufferMinutes: settings.departureBufferMinutes,
      now: _clock.now(),
    );
  }
}
