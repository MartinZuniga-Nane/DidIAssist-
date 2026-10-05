import 'package:did_i_assist/src/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

final class DidIAssistApp extends StatelessWidget {
  const DidIAssistApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    title: 'DidIAssist',
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: Center(child: Text('DidIAssist'))),
  );
}
