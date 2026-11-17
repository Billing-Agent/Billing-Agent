import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/widgets/payment_result_dialog.dart';

void main() {
  Widget buildDialog({
    required String status,
    VoidCallback? onRetry,
  }) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => PaymentResultDialog(
                  status: status,
                  title: 'Payment $status',
                  transactionId: 'tx-123',
                  amount: '7200.00',
                  currency: 'LKR',
                  message: status == 'PENDING'
                      ? 'Your payment is still being confirmed.'
                      : null,
                  onRetry: onRetry,
                  onPrimary: () => Navigator.of(context).pop(),
                ),
              ),
              child: const Text('Show result'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('success result identifies backend/provider verification',
      (tester) async {
    await tester.pumpWidget(buildDialog(status: 'SUCCESS'));
    await tester.tap(find.text('Show result'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('payment_result_dialog')), findsOneWidget);
    expect(find.text('SUCCESS'), findsOneWidget);
    expect(find.text('LKR 7,200.00'), findsOneWidget);
    expect(
      find.text(
        'Verified from PayHere provider status by the Billing Agent backend.',
      ),
      findsOneWidget,
    );
    expect(find.text('View Bills'), findsOneWidget);
  });

  testWidgets('pending result never implies local checkout completion is final',
      (tester) async {
    await tester.pumpWidget(buildDialog(status: 'PENDING'));
    await tester.tap(find.text('Show result'));
    await tester.pumpAndSettle();

    expect(find.text('PENDING'), findsOneWidget);
    expect(
      find.text(
        'PayHere and the backend are still confirming the final payment status.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('payment_result_tx_id')), findsOneWidget);
  });

  testWidgets('failed result keeps retry action and transaction reference',
      (tester) async {
    var retryCount = 0;
    await tester.pumpWidget(
      buildDialog(status: 'FAILED', onRetry: () => retryCount++),
    );
    await tester.tap(find.text('Show result'));
    await tester.pumpAndSettle();

    expect(find.text('FAILED'), findsOneWidget);
    expect(find.text('Transaction ID: tx-123'), findsOneWidget);
    await tester.tap(find.byKey(const Key('payment_result_retry_button')));
    expect(retryCount, 1);
  });

  testWidgets('cancelled result states that success was not confirmed',
      (tester) async {
    await tester.pumpWidget(buildDialog(status: 'CANCELLED'));
    await tester.tap(find.text('Show result'));
    await tester.pumpAndSettle();

    expect(find.text('CANCELLED'), findsOneWidget);
    expect(
      find.text('No successful payment has been confirmed by the backend.'),
      findsOneWidget,
    );
  });

  testWidgets('unknown result uses neutral unavailable-status guidance',
      (tester) async {
    await tester.pumpWidget(buildDialog(status: 'UNEXPECTED'));
    await tester.tap(find.text('Show result'));
    await tester.pumpAndSettle();

    expect(find.text('UNKNOWN'), findsOneWidget);
    expect(find.text('UNEXPECTED'), findsNothing);
    expect(
      find.text(
        'The payment status is unavailable. Review your transaction history for the latest backend status.',
      ),
      findsOneWidget,
    );
  });
}
