import 'package:did_i_attend/src/domain/location/geofence_transition.dart';

// A named interface supports injectable storage-backed handlers at bootstrap.
// ignore: one_member_abstracts
abstract interface class BackgroundLocationHandler {
  Future<void> handle(GeofenceTransition transition);
}
