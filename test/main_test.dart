import 'package:did_i_assist/src/app/didi_assist_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('launches the placeholder app', (tester) async {
    await tester.pumpWidget(const DidIAssistApp());

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('DidIAssist'), findsOneWidget);
  });
}
