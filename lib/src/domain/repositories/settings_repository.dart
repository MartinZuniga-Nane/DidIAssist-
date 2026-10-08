import 'package:did_i_attend/src/domain/models/user_settings.dart';

abstract interface class SettingsRepository {
  /// Returns default settings when none have been saved.
  Future<UserSettings> load();
  Stream<UserSettings> watch();
  Future<void> save(UserSettings settings);
}
