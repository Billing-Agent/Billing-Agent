import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/models/agent_message.dart';
import 'package:mobile/models/bill.dart';
import 'package:mobile/models/payment_plan.dart';
import 'package:mobile/models/transaction.dart';
import 'package:mobile/widgets/amount_text.dart';
import 'package:mobile/widgets/bill_card.dart';
import 'package:mobile/widgets/payment_plan_card.dart';
import 'package:mobile/widgets/primary_button.dart';
import 'package:mobile/widgets/state_views.dart';
import 'package:mobile/widgets/status_chip.dart';
import 'package:mobile/widgets/transaction_card.dart';

void main() {
  test('light and dark themes expose compatible semantic colors', () {
    final light = AppTheme.lightTheme;
    final dark = AppTheme.darkTheme;
    final lightSemantic = light.extension<AppSemanticColors>();
    final darkSemantic = dark.extension<AppSemanticColors>();

    expect(light.useMaterial3, isTrue);
    expect(dark.useMaterial3, isTrue);
    expect(lightSemantic, isNotNull);
    expect(darkSemantic, isNotNull);
    expect(lightSemantic!.success, isNot(lightSemantic.pending));
    expect(darkSemantic!.success, isNot(darkSemantic.pending));
    expect(light.cardTheme.elevation, 0);
    expect(dark.cardTheme.elevation, 0);
  });

  testWidgets('StatusChip presents known and unknown states semantically',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: Column(
            children: [
              StatusChip(status: 'SUCCESS'),
              StatusChip(status: 'PENDING'),
              StatusChip(status: 'CUSTOM'),
              StatusChip(status: ''),
            ],
          ),
        ),
      ),
    );

    expect(find.text('SUCCESS'), findsOneWidget);
    expect(find.text('PENDING'), findsOneWidget);
    expect(find.text('CUSTOM'), findsOneWidget);
    expect(find.text('UNKNOWN'), findsOneWidget);
    expect(find.bySemanticsLabel('SUCCESS status'), findsOneWidget);
    expect(find.bySemanticsLabel('PENDING status'), findsOneWidget);
    expect(find.bySemanticsLabel('CUSTOM status'), findsOneWidget);
    expect(find.bySemanticsLabel('UNKNOWN status'), findsOneWidget);
  });

  testWidgets('AmountText preserves string-based money formatting',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: AmountText(amount: '7200.00', currency: 'LKR'),
        ),
      ),
    );

    expect(find.text('LKR 7,200.00'), findsOneWidget);
  });

  testWidgets('loading PrimaryButton disables actions with visible progress',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: PrimaryButton(
            label: 'Continue',
            isLoading: true,
            onPressed: () {},
          ),
        ),
      ),
    );

    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    final indicator = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );

    expect(button.onPressed, isNull);
    expect(indicator.color, AppTheme.lightTheme.colorScheme.primary);
  });

  testWidgets('financial cards remain usable in dark mode at narrow width',
      (tester) async {
    final bill = Bill(
      id: 'bill-1',
      biller: 'A very long electricity provider name',
      accountNumber: '1234567890',
      amountDue: '1234567890.00',
      currency: 'LKR',
      status: 'UNPAID',
      dueDate: DateTime(2026, 12, 31),
    );
    const plan = PaymentPlan(
      billId: 'bill-1',
      biller: 'A very long electricity provider name',
      accountNumber: '1234567890',
      amount: '1234567890.00',
      currency: 'LKR',
      billStatus: 'UNPAID',
    );
    final transaction = Transaction(
      id: 'transaction-1',
      biller: 'A very long electricity provider name',
      amount: '1234567890.00',
      currency: 'LKR',
      status: 'PENDING',
      createdAt: DateTime(2026, 11, 16),
    );

    await tester.pumpWidget(
      MaterialApp(
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 800),
              textScaler: TextScaler.linear(1.3),
            ),
            child: SingleChildScrollView(
              child: SizedBox(
                width: 320,
                child: Column(
                  children: [
                    BillCard(bill: bill),
                    PaymentPlanCard(
                      plan: plan,
                      cardState: PaymentPlanCardState.pending,
                      isConfirming: false,
                      onConfirm: () {},
                      onCancel: () {},
                    ),
                    TransactionCard(transaction: transaction),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('UNPAID'), findsNWidgets(2));
    expect(find.text('Confirm Payment'), findsOneWidget);
    expect(find.text('LKR 1,234,567,890.00'), findsNWidgets(3));
  });

  testWidgets('shared state views retain recovery actions', (tester) async {
    var emptyActionCount = 0;
    var retryCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Column(
            children: [
              Expanded(
                child: EmptyStateView(
                  message: 'No bills',
                  actionLabel: 'Refresh',
                  onAction: () => emptyActionCount++,
                ),
              ),
              Expanded(
                child: ErrorStateView(
                  error: 'Unable to load',
                  onRetry: () => retryCount++,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Refresh'));
    await tester.tap(find.text('Retry'));

    expect(emptyActionCount, 1);
    expect(retryCount, 1);
  });
}
