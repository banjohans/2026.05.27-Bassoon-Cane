import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:reedlab/app.dart';

void main() {
  testWidgets('App shell renders', (WidgetTester tester) async {
    await tester.pumpWidget(const BassoonCaneApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(Scaffold), findsWidgets);
  });
}
