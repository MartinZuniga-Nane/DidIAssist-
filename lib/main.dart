import 'package:did_i_assist/src/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(
    const MaterialApp(
      title: 'DidIAssist',
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: Text('DidIAssist'))),
    ),
  );
}
