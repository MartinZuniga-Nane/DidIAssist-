import 'package:clock/clock.dart';
import 'package:did_i_attend/src/core/local_date.dart';

DateTime utcNow({Clock? timeSource}) => (timeSource ?? clock).now().toUtc();

LocalDate today({Clock? timeSource}) =>
    LocalDate.fromDateTime((timeSource ?? clock).now());
