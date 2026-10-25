import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/models/bill.dart';
import 'package:mobile/models/payment_method.dart';
import 'package:mobile/models/payhere_initiate.dart';
import 'package:mobile/models/transaction.dart';
import 'package:mobile/repositories/payment_repository.dart';
import 'package:mobile/repositories/bill_repository.dart';
import 'package:mobile/screens/payment/payment_confirmation_screen.dart';
import 'package:mobile/services/payhere_checkout_service.dart';

class MockPayHereCheckoutService implements PayHereCheckoutService {
  PayHereInitiateResponse? lastInitiateResponse;
  String? lastMerchantSecret;
  void Function(String paymentId)? onCompletedCallback;
  void Function(String error)? onErrorCallback;
  void Function()? onDismissedCallback;
  int launchCount = 0;

  // Configuration for auto-responding
  String? autoTrigger; // 'complete', 'error', 'dismiss', or null

  @override
  void startPayment({
    required PayHereInitiateResponse initiateResponse,
    required void Function(String paymentId) onCompleted,
    required void Function(String error) onError,
    required void Function() onDismissed,
    bool isSandbox = true,
    String? merchantSecret,
  }) {
    launchCount++;
    lastInitiateResponse = initiateResponse;
    lastMerchantSecret = merchantSecret;
    onCompletedCallback = onCompleted;
    onErrorCallback = onError;
    onDismissedCallback = onDismissed;

    if (autoTrigger == 'complete') {
      onCompleted('payhere_ref_999');
    } else if (autoTrigger == 'error') {
      onError('Card declined by gateway');
    } else if (autoTrigger == 'dismiss') {
      onDismissed();
    }
  }
}

class FakePaymentRepository implements PaymentRepository {
  int prepareCount = 0;
  int initiateCount = 0;
  int getStatusCount = 0;

  String returnedTransactionId = 'tx-test-uuid-001';
  String backendTransactionStatus = 'SUCCESS';

  @override
  Future<List<PaymentMethod>> getUserPaymentMethods() async {
    return [
      const PaymentMethod(
        id: 'pm-1',
        provider: 'PAYHERE',
        cardBrand: 'VISA',
        lastFour: '4242',
        isDefault: true,
      ),
    ];
  }

  @override
  Future<List<Transaction>> getUserTransactions() async => [];

  @override
  Future<Transaction> preparePayment(String billId, String paymentMethodId, String idempotencyKey) async {
    prepareCount++;
    return Transaction(
      id: returnedTransactionId,
      biller: 'CEB',
      amount: '1500.00',
      currency: 'LKR',
      status: 'PENDING',
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<PayHereInitiateResponse> initiatePayment(String transactionId) async {
    initiateCount++;
    return PayHereInitiateResponse(
      merchantId: '1211149',
      orderId: transactionId,
      items: 'CEB Electricity Bill',
      currency: 'LKR',
      amount: '1500.00',
      firstName: 'Dev',
      lastName: 'User',
      email: 'dev@example.com',
      phone: '+94771234567',
      address: 'Main St',
      city: 'Colombo',
      country: 'Sri Lanka',
      returnUrl: 'http://localhost/return',
      cancelUrl: 'http://localhost/cancel',
      notifyUrl: 'http://localhost/notify',
      hash: 'MD5HASH12345',
    );
  }

  @override
  Future<Transaction?> getPaymentStatus(String transactionId) async {
    getStatusCount++;
    return Transaction(
      id: transactionId,
      biller: 'CEB',
      amount: '1500.00',
      currency: 'LKR',
      status: backendTransactionStatus,
      createdAt: DateTime.now(),
    );
  }
}

class FakeBillRepository implements BillRepository {
  int billsFetchCount = 0;

  @override
  Future<List<Bill>> getUserBills() async {
    billsFetchCount++;
    return [];
  }

  @override
  Future<Bill?> getBillById(String id) async => null;
}

void main() {
  final testBill = Bill(
    id: 'bill-001',
    biller: 'CEB',
    accountNumber: 'ACC123456',
    amountDue: '1500.00',
    currency: 'LKR',
    status: 'UNPAID',
    dueDate: DateTime(2026, 12, 31),
  );

  Widget createWidget({
    required FakePaymentRepository paymentRepo,
    required MockPayHereCheckoutService checkoutService,
    FakeBillRepository? billRepo,
  }) {
    return ProviderScope(
      overrides: [
        paymentRepositoryProvider.overrideWithValue(paymentRepo),
        payHereCheckoutServiceProvider.overrideWithValue(checkoutService),
        if (billRepo != null) billRepositoryProvider.overrideWithValue(billRepo),
      ],
      child: MaterialApp(
        home: PaymentConfirmationScreen(bill: testBill),
      ),
    );
  }

  group('PaymentConfirmationScreen PayHere Flow', () {
    testWidgets('prepare followed by initiate and launches PayHere checkout', (tester) async {
      final paymentRepo = FakePaymentRepository();
      final checkoutService = MockPayHereCheckoutService();

      await tester.pumpWidget(createWidget(
        paymentRepo: paymentRepo,
        checkoutService: checkoutService,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Confirm Payment'), findsWidgets);
      expect(find.byKey(const Key('confirm_payment_button')), findsOneWidget);

      // Tap Confirm Payment
      await tester.tap(find.byKey(const Key('confirm_payment_button')));
      await tester.pump();

      expect(paymentRepo.prepareCount, 1);
      expect(paymentRepo.initiateCount, 1);
      expect(checkoutService.launchCount, 1);
      expect(checkoutService.lastInitiateResponse?.orderId, 'tx-test-uuid-001');
      expect(checkoutService.lastInitiateResponse?.hash, 'MD5HASH12345');
    });

    testWidgets('duplicate Confirm tap protection prevents repeated prepare and initiate calls', (tester) async {
      final paymentRepo = FakePaymentRepository();
      final checkoutService = MockPayHereCheckoutService();

      await tester.pumpWidget(createWidget(
        paymentRepo: paymentRepo,
        checkoutService: checkoutService,
      ));
      await tester.pumpAndSettle();

      // Tap twice rapidly
      await tester.tap(find.byKey(const Key('confirm_payment_button')));
      await tester.tap(find.byKey(const Key('confirm_payment_button')));
      await tester.pump();

      expect(paymentRepo.prepareCount, 1);
      expect(paymentRepo.initiateCount, 1);
      expect(checkoutService.launchCount, 1);
    });

    testWidgets('SUCCESS result rendering: authoritative backend status renders success dialog and refreshes state', (tester) async {
      final paymentRepo = FakePaymentRepository()..backendTransactionStatus = 'SUCCESS';
      final checkoutService = MockPayHereCheckoutService()..autoTrigger = 'complete';
      final billRepo = FakeBillRepository();

      await tester.pumpWidget(createWidget(
        paymentRepo: paymentRepo,
        checkoutService: checkoutService,
        billRepo: billRepo,
      ));
      await tester.pumpAndSettle();

      // Tap Confirm Payment
      await tester.tap(find.byKey(const Key('confirm_payment_button')));
      await tester.pumpAndSettle();

      // Verify PayHere client callback did not directly mark success — backend was queried!
      expect(paymentRepo.getStatusCount, greaterThanOrEqualTo(1));

      // Verify SUCCESS result dialog
      expect(find.byKey(const Key('payment_result_dialog')), findsOneWidget);
      expect(find.text('Payment Successful'), findsOneWidget);
      expect(find.text('Amount: LKR 1500.00'), findsOneWidget);
      expect(find.text('Transaction ID: tx-test-uuid-001'), findsOneWidget);

      // Verify old message is NOT shown
      expect(find.textContaining('Actual payment processing is not implemented yet'), findsNothing);
    });

    testWidgets('backend status is used instead of trusting client callback (backend says FAILED despite client complete)', (tester) async {
      final paymentRepo = FakePaymentRepository()..backendTransactionStatus = 'FAILED';
      final checkoutService = MockPayHereCheckoutService()..autoTrigger = 'complete';

      await tester.pumpWidget(createWidget(
        paymentRepo: paymentRepo,
        checkoutService: checkoutService,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('confirm_payment_button')));
      await tester.pumpAndSettle();

      // Status check was authoritative
      expect(paymentRepo.getStatusCount, greaterThanOrEqualTo(1));
      expect(find.text('Payment Failed'), findsOneWidget);
      expect(find.text('Payment Successful'), findsNothing);
      expect(find.byKey(const Key('payment_result_retry_button')), findsOneWidget);
    });

    testWidgets('CANCELLED result rendering when checkout is dismissed and backend is CANCELLED', (tester) async {
      final paymentRepo = FakePaymentRepository()..backendTransactionStatus = 'CANCELLED';
      final checkoutService = MockPayHereCheckoutService()..autoTrigger = 'dismiss';

      await tester.pumpWidget(createWidget(
        paymentRepo: paymentRepo,
        checkoutService: checkoutService,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('confirm_payment_button')));
      await tester.pumpAndSettle();

      expect(paymentRepo.getStatusCount, greaterThanOrEqualTo(1));
      expect(find.text('Payment Cancelled'), findsOneWidget);
      expect(find.text('Transaction ID: tx-test-uuid-001'), findsOneWidget);
    });

    testWidgets('PENDING result rendering: shows processing and confirmation message', (tester) async {
      final paymentRepo = FakePaymentRepository()..backendTransactionStatus = 'PENDING';
      final checkoutService = MockPayHereCheckoutService()..autoTrigger = 'complete';

      await tester.pumpWidget(createWidget(
        paymentRepo: paymentRepo,
        checkoutService: checkoutService,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('confirm_payment_button')));
      await tester.pumpAndSettle();

      expect(find.text('Payment Processing'), findsOneWidget);
      expect(find.text('Your payment is still being confirmed.'), findsOneWidget);
      expect(find.text('Transaction ID: tx-test-uuid-001'), findsOneWidget);
      expect(find.textContaining('Actual payment processing is not implemented yet'), findsNothing);
    });
  });
}
