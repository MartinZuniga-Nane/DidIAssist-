import 'package:did_i_attend/src/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

final class DidIAttendApp extends StatelessWidget {
  const DidIAttendApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    title: 'DidIAttend',
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: Center(child: Text('DidIAttend'))),
  );
}
