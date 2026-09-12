import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/main.dart';
import 'package:mobile/widgets/state_views.dart';

void main() {
  testWidgets('App starts successfully and renders Home screen', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ProviderScope(child: BillingAgentApp()));
    await tester.pumpAndSettle(); // wait for animations and futures

    // Verify that the home screen is displayed
    expect(find.text('Billing Agent'), findsOneWidget);
    expect(find.text('Good morning, Nafris'), findsOneWidget);
    expect(find.text('Upcoming Bills'), findsOneWidget);
  });

  testWidgets('Bottom navigation works and renders Bills screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: BillingAgentApp()));
    await tester.pumpAndSettle();

    // Tap on the Bills tab
    await tester.tap(find.byIcon(Icons.receipt_long_outlined).first);
    await tester.pumpAndSettle();

    // Verify Bills screen
    expect(find.text('My Bills'), findsOneWidget);
    // Since mock data loads with a delay, we pump to let it load
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    
    // Look for CEB bill
    expect(find.text('CEB'), findsWidgets);
  });

  testWidgets('Empty state view renders correctly', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EmptyStateView(message: 'Test empty state'),
        ),
      ),
    );

    expect(find.text('Test empty state'), findsOneWidget);
    expect(find.byIcon(Icons.inbox), findsOneWidget);
  });
}
