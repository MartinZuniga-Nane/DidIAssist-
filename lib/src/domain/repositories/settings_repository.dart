import 'package:did_i_assist/src/domain/models/user_settings.dart';

abstract interface class SettingsRepository {
  /// Returns default settings when none have been saved.
  Future<UserSettings> load();
  Future<void> save(UserSettings settings);
}
