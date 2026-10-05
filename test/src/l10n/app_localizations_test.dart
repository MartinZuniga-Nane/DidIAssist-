import 'package:did_i_assist/src/l10n/generated/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (locale, title) in [
    (const Locale('en'), 'Attendance recorded'),
    (const Locale('es'), 'Asistencia registrada'),
    (const Locale('es', 'MX'), 'Asistencia registrada'),
  ]) {
    test('loads $locale without a BuildContext', () {
      final strings = lookupAppLocalizations(locale);
      expect(strings.attendanceRecordedTitle, title);
      expect(strings.departureChannelName, isNotEmpty);
      expect(strings.attendanceChannelDescription, isNotEmpty);
    });
  }

  test('English template and Spanish expose the same supported locales', () {
    expect(AppLocalizations.supportedLocales, [
      const Locale('en'),
      const Locale('es'),
    ]);
  });
}
