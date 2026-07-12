import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:formuladoc/main.dart';

void main() {
  testWidgets('App renders HomeScreen without crashing', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: FormulaDocApp(),
      ),
    );

    // Wait for async initialisation
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Home screen should render the app name
    expect(find.text('FormulaDoc'), findsWidgets);
  });

  testWidgets('HomeScreen shows Open File button', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: FormulaDocApp(),
      ),
    );

    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('Open File'), findsOneWidget);
  });
}
