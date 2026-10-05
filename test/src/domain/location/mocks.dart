import 'package:did_i_assist/src/domain/location/background_location_handler.dart';
import 'package:did_i_assist/src/domain/location/geofence_registrar.dart';
import 'package:did_i_assist/src/domain/location/position_provider.dart';
import 'package:did_i_assist/src/domain/repositories/location_event_repository.dart';
import 'package:did_i_assist/src/domain/repositories/place_repository.dart';
import 'package:mocktail/mocktail.dart';

final class MockPlaceRepository extends Mock implements PlaceRepository {}

final class MockGeofenceRegistrar extends Mock implements GeofenceRegistrar {}

final class MockLocationEventRepository extends Mock
    implements LocationEventRepository {}

final class MockPositionProvider extends Mock implements PositionProvider {}

final class MockBackgroundLocationHandler extends Mock
    implements BackgroundLocationHandler {}
