import 'package:did_i_assist/src/data/database/app_database.dart';
import 'package:did_i_assist/src/data/database/mappers/settings_mapping.dart';
import 'package:did_i_assist/src/domain/models/user_settings.dart';
import 'package:did_i_assist/src/domain/repositories/settings_repository.dart';

final class DriftSettingsRepository implements SettingsRepository {
  DriftSettingsRepository(this._database);

  final AppDatabase _database;

  @override
  Future<UserSettings> load() async {
    final row = await (_database.select(
      _database.userSettingsTable,
    )..where((table) => table.id.equals(1))).getSingleOrNull();
    return row == null ? UserSettings() : settingsFromRow(row);
  }

  @override
  Future<void> save(UserSettings settings) async {
    await _database
        .into(_database.userSettingsTable)
        .insertOnConflictUpdate(
          settingsToCompanion(settings),
        );
  }

  @override
  Stream<UserSettings> watch() =>
      (_database.select(
            _database.userSettingsTable,
          )..where((table) => table.id.equals(1)))
          .watchSingleOrNull()
          .map(
            (row) => row == null ? UserSettings() : settingsFromRow(row),
          )
          .distinct();
}
