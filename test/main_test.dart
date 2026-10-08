import 'package:did_i_attend/src/app/didi_attend_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('launches the placeholder app', (tester) async {
    await tester.pumpWidget(const DidIAttendApp());

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('DidIAttend'), findsOneWidget);
  });
}
