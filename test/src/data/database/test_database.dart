import 'package:did_i_attend/src/data/database/app_database.dart';
import 'package:drift/native.dart';

AppDatabase createTestDatabase() =>
    AppDatabase.forTesting(NativeDatabase.memory());
