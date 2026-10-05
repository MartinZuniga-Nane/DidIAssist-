import 'package:did_i_assist/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('launches the placeholder app', (tester) async {
    app.main();
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('DidIAssist'), findsOneWidget);
  });
}
