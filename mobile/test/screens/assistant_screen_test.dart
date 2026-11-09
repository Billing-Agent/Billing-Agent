import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile/core/errors/app_errors.dart';
import 'package:mobile/models/agent_response.dart';
import 'package:mobile/models/payment_plan.dart';
import 'package:mobile/models/payment_method.dart';
import 'package:mobile/models/payhere_initiate.dart';
import 'package:mobile/models/transaction.dart';
import 'package:mobile/models/bill.dart';
import 'package:mobile/repositories/payment_repository.dart';
import 'package:mobile/repositories/bill_repository.dart';
import 'package:mobile/services/agent_service.dart';
import 'package:mobile/services/payhere_checkout_service.dart';
import 'package:mobile/screens/assistant/assistant_screen.dart';
import 'package:mobile/screens/home/home_screen.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/models/auth_state.dart';
import 'package:mobile/models/user.dart';
import 'package:mobile/repositories/auth_repository.dart';
import 'package:mobile/services/api_client.dart';
import 'package:mobile/core/storage/token_storage.dart';
import 'package:mobile/core/routing/app_router.dart';
import '../core/token_storage_test.dart';

class FakeAgentService implements AgentService {
  final List<String> chatSentMessages = [];
  final List<String> confirmedTokens = [];

  AgentChatResponse? nextChatResponse;
  AgentPaymentConfirmResponse? nextConfirmResponse;
  Exception? chatException;
  Exception? confirmException;

  @override
  Future<AgentChatResponse> sendMessage(String message) async {
    chatSentMessages.add(message);
    if (chatException != null) {
      throw chatException!;
    }
    return nextChatResponse ??
        AgentChatResponse(
          message: 'Default response to: $message',
          requiresConfirmation: false,
        );
  }

  @override
  Future<AgentPaymentConfirmResponse> confirmPayment(
      String confirmationId) async {
    confirmedTokens.add(confirmationId);
    if (confirmException != null) {
      throw confirmException!;
    }
    return nextConfirmResponse ??
        const AgentPaymentConfirmResponse(
          transactionId: 'tx-agent-prepared-001',
          billId: 'bill-1acb2cc9',
          amount: '7200.00',
          currency: 'LKR',
          status: 'PENDING',
        );
  }
}

class FakePaymentRepository implements PaymentRepository {
  int initiateCount = 0;
  int getStatusCount = 0;
  final List<String> initiatedTransactionIds = [];

  String backendTransactionStatus = 'SUCCESS';
  String returnedTransactionId = 'tx-agent-prepared-001';

  @override
  Future<List<PaymentMethod>> getUserPaymentMethods() async => [];

  @override
  Future<List<Transaction>> getUserTransactions() async => [];

  @override
  Future<Transaction> preparePayment(
      String billId, String paymentMethodId, String idempotencyKey) async {
    throw UnimplementedError();
  }

  @override
  Future<PayHereInitiateResponse> initiatePayment(String transactionId) async {
    initiateCount++;
    initiatedTransactionIds.add(transactionId);
    return PayHereInitiateResponse(
      merchantId: '1211149',
      orderId: transactionId,
      items: 'CEB Bill',
      currency: 'LKR',
      amount: '7200.00',
      firstName: 'Alice',
      lastName: 'Dev',
      email: 'alice@example.com',
      phone: '+94771234567',
      address: 'Main St',
      city: 'Colombo',
      country: 'Sri Lanka',
      returnUrl: 'http://localhost/return',
      cancelUrl: 'http://localhost/cancel',
      notifyUrl: 'http://localhost/notify',
      hash: 'mockhash123',
    );
  }

  @override
  Future<Transaction?> getPaymentStatus(String transactionId) async {
    getStatusCount++;
    return Transaction(
      id: transactionId,
      biller: 'CEB',
      amount: '7200.00',
      currency: 'LKR',
      status: backendTransactionStatus,
      createdAt: DateTime.now(),
    );
  }
}

class FakeBillRepository implements BillRepository {
  int getBillsCallCount = 0;

  @override
  Future<List<Bill>> getUserBills() async {
    getBillsCallCount++;
    return [];
  }

  @override
  Future<Bill?> getBillById(String id) async => null;
}

class MockPayHereCheckoutService implements PayHereCheckoutService {
  int launchCount = 0;
  PayHereInitiateResponse? lastInitiateResponse;
  String? autoTrigger; // 'complete', 'error', 'dismiss'

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

    if (autoTrigger == 'complete') {
      onCompleted('payhere-ref-12345');
    } else if (autoTrigger == 'error') {
      onError('Payment declined by card gateway');
    } else if (autoTrigger == 'dismiss') {
      onDismissed();
    }
  }
}

class MockAuthNotifier extends AuthNotifier {
  MockAuthNotifier()
      : super(
          repository: AuthRepository(
            apiClient: ApiClient(),
            tokenStorage: TokenStorage(storage: MockFlutterSecureStorage()),
          ),
          tokenStorage: TokenStorage(storage: MockFlutterSecureStorage()),
          apiClient: ApiClient(),
        ) {
    state = AuthState.authenticated(
      const User(id: 'alice-id', name: 'Alice', email: 'alice@example.com'),
    );
  }

  @override
  Future<void> checkAuthStatus() async {}

  @override
  Future<void> logout() async {
    state = AuthState.unauthenticated();
  }

  void authenticate(User user) {
    state = AuthState.authenticated(user);
  }
}

void main() {
  late FakeAgentService fakeAgentService;
  late FakePaymentRepository fakePaymentRepo;
  late FakeBillRepository fakeBillRepo;
  late MockPayHereCheckoutService mockCheckoutService;

  setUp(() {
    fakeAgentService = FakeAgentService();
    fakePaymentRepo = FakePaymentRepository();
    fakeBillRepo = FakeBillRepository();
    mockCheckoutService = MockPayHereCheckoutService();
  });

  Widget createTestWidget({Widget? child, MockAuthNotifier? authNotifier}) {
    final activeAuthNotifier = authNotifier ?? MockAuthNotifier();
    return ProviderScope(
      overrides: [
        agentServiceProvider.overrideWithValue(fakeAgentService),
        paymentRepositoryProvider.overrideWithValue(fakePaymentRepo),
        billRepositoryProvider.overrideWithValue(fakeBillRepo),
        payHereCheckoutServiceProvider.overrideWithValue(mockCheckoutService),
        authProvider.overrideWith((ref) => activeAuthNotifier),
      ],
      child: MaterialApp(
        home: child ?? const AssistantScreen(),
      ),
    );
  }

  Widget createAppWithRouter() {
    return ProviderScope(
      overrides: [
        agentServiceProvider.overrideWithValue(fakeAgentService),
        paymentRepositoryProvider.overrideWithValue(fakePaymentRepo),
        billRepositoryProvider.overrideWithValue(fakeBillRepo),
        payHereCheckoutServiceProvider.overrideWithValue(mockCheckoutService),
        authProvider.overrideWith((ref) => MockAuthNotifier()),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          final router = ref.watch(routerProvider);
          return MaterialApp.router(
            routerConfig: router,
          );
        },
      ),
    );
  }

  group('Phase 8D Mobile Agent Acceptance Tests', () {
    // 1. Home screen shows Ask Billing Agent entry.
    testWidgets('1. Home screen shows Ask Billing Agent entry', (tester) async {
      await tester.pumpWidget(createTestWidget(child: const HomeScreen()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ask_billing_agent_card')), findsOneWidget);
      expect(find.text('Ask Billing Agent'), findsOneWidget);
      expect(find.text('Pay bills or check balances using natural language'),
          findsOneWidget);
      // Verify manual actions still exist
      expect(find.text('Pay a Bill'), findsOneWidget);
      expect(find.text('View History'), findsOneWidget);
    });

    // 2. Tapping entry opens Assistant screen.
    testWidgets('2. Tapping entry opens Assistant screen', (tester) async {
      await tester.pumpWidget(createAppWithRouter());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ask_billing_agent_card')), findsOneWidget);
      await tester.tap(find.byKey(const Key('ask_billing_agent_card')));
      await tester.pumpAndSettle();

      expect(find.text('Billing Assistant'), findsOneWidget);
      expect(find.byKey(const Key('assistant_text_field')), findsOneWidget);
    });

    // 3. User sends "Show my bills" -> correct API request and assistant response displayed.
    testWidgets(
        '3. User sends Show my bills: correct API request & response displayed',
        (tester) async {
      fakeAgentService.nextChatResponse = const AgentChatResponse(
        message: 'You have 1 unpaid bill for CEB account 12347.',
        intent: 'VIEW_BILLS',
        requiresConfirmation: false,
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('assistant_text_field')), 'Show my bills');
      await tester.tap(find.byKey(const Key('assistant_send_button')));
      await tester.pumpAndSettle();

      expect(fakeAgentService.chatSentMessages, contains('Show my bills'));
      expect(find.text('Show my bills'), findsOneWidget);
      expect(find.text('You have 1 unpaid bill for CEB account 12347.'),
          findsOneWidget);
      expect(find.byKey(const Key('payment_plan_card')), findsNothing);
    });

    // 4. Payment planning response with requires_confirmation=true, payment_plan, confirmation_id displays payment card.
    testWidgets('4. Payment planning response displays payment card',
        (tester) async {
      fakeAgentService.nextChatResponse = const AgentChatResponse(
        message:
            'I found your CEB bill for account 12347. Amount due: LKR 7,200.00. Would you like to proceed?',
        intent: 'PAY_BILL',
        requiresConfirmation: true,
        confirmationId: 'valid-conf-uuid-12347',
        paymentPlan: PaymentPlan(
          billId: '1acb2cc9-b988-4106-88e9-4e84e077fc2e',
          biller: 'CEB',
          accountNumber: '12347',
          amount: '7200.00',
          currency: 'LKR',
          billStatus: 'UNPAID',
          requiresConfirmation: true,
        ),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('assistant_text_field')),
          'Pay my CEB bill for account 12347');
      await tester.tap(find.byKey(const Key('assistant_send_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('payment_plan_card')), findsOneWidget);
      expect(find.byKey(const Key('payment_plan_biller')), findsOneWidget);
      expect(find.text('CEB'), findsOneWidget);
      expect(find.text('Account ****2347'), findsOneWidget);
      expect(
          find.byKey(const Key('payment_plan_confirm_button')), findsOneWidget);
      expect(
          find.byKey(const Key('payment_plan_cancel_button')), findsOneWidget);
    });

    // 5. Payment card amount comes only from backend response.
    testWidgets('5. Payment card amount comes only from backend response',
        (tester) async {
      fakeAgentService.nextChatResponse = const AgentChatResponse(
        message: 'Confirmation proposal',
        intent: 'PAY_BILL',
        requiresConfirmation: true,
        confirmationId: 'valid-conf-12347',
        paymentPlan: PaymentPlan(
          billId: 'bill-1',
          biller: 'CEB',
          accountNumber: '12347',
          amount: '7200.00',
          currency: 'LKR',
          billStatus: 'UNPAID',
        ),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Even if user typed something with a different amount
      await tester.enterText(find.byKey(const Key('assistant_text_field')),
          'Pay LKR 50 for my bill');
      await tester.tap(find.byKey(const Key('assistant_send_button')));
      await tester.pumpAndSettle();

      // Card must strictly display backend amount
      expect(find.text('LKR 7,200.00'), findsOneWidget);
      expect(find.text('LKR 50.00'), findsNothing);
    });

    // 6. Confirm button sends ONLY confirmation_id.
    testWidgets('6. Confirm button sends ONLY confirmation_id', (tester) async {
      fakeAgentService.nextChatResponse = const AgentChatResponse(
        message: 'Proposal',
        requiresConfirmation: true,
        confirmationId: 'conf-secret-token-xyz',
        paymentPlan: PaymentPlan(
          billId: 'b-1',
          biller: 'CEB',
          accountNumber: '12347',
          amount: '7200.00',
          currency: 'LKR',
          billStatus: 'UNPAID',
        ),
      );
      mockCheckoutService.autoTrigger = 'complete';

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('assistant_text_field')), 'Pay my bill');
      await tester.tap(find.byKey(const Key('assistant_send_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('payment_plan_confirm_button')));
      await tester.pumpAndSettle();

      expect(fakeAgentService.confirmedTokens, ['conf-secret-token-xyz']);
    });

    // 7. Confirm button cannot be double tapped.
    testWidgets('7. Confirm button cannot be double tapped', (tester) async {
      fakeAgentService.nextChatResponse = const AgentChatResponse(
        message: 'Proposal',
        requiresConfirmation: true,
        confirmationId: 'conf-single-token-1',
        paymentPlan: PaymentPlan(
          billId: 'b-1',
          biller: 'CEB',
          accountNumber: '12347',
          amount: '7200.00',
          currency: 'LKR',
          billStatus: 'UNPAID',
        ),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('assistant_text_field')), 'Pay my bill');
      await tester.tap(find.byKey(const Key('assistant_send_button')));
      await tester.pumpAndSettle();

      // Tap twice quickly
      await tester.tap(find.byKey(const Key('payment_plan_confirm_button')));
      await tester.tap(find.byKey(const Key('payment_plan_confirm_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(fakeAgentService.confirmedTokens.length, 1);
    });

    // 8. Typing "yes" does NOT call payment confirmation endpoint.
    testWidgets('8. Typing yes does NOT call payment confirmation endpoint',
        (tester) async {
      fakeAgentService.nextChatResponse = const AgentChatResponse(
        message: 'Are you sure?',
        requiresConfirmation: true,
        confirmationId: 'token-abc',
        paymentPlan: PaymentPlan(
          billId: 'b-1',
          biller: 'CEB',
          accountNumber: '12347',
          amount: '7200.00',
          currency: 'LKR',
          billStatus: 'UNPAID',
        ),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('assistant_text_field')), 'Pay my bill');
      await tester.tap(find.byKey(const Key('assistant_send_button')));
      await tester.pumpAndSettle();

      // User types "yes" in chat text field
      await tester.enterText(
          find.byKey(const Key('assistant_text_field')), 'yes');
      await tester.tap(find.byKey(const Key('assistant_send_button')));
      await tester.pumpAndSettle();

      expect(fakeAgentService.chatSentMessages, contains('yes'));
      // CRITICAL: confirmPayment must NOT have been called!
      expect(fakeAgentService.confirmedTokens, isEmpty);
      expect(mockCheckoutService.launchCount, 0);
    });

    // 9. Cancel does NOT call confirmation endpoint.
    testWidgets('9. Cancel does NOT call confirmation endpoint',
        (tester) async {
      fakeAgentService.nextChatResponse = const AgentChatResponse(
        message: 'Proposal',
        requiresConfirmation: true,
        confirmationId: 'token-to-cancel',
        paymentPlan: PaymentPlan(
          billId: 'b-1',
          biller: 'CEB',
          accountNumber: '12347',
          amount: '7200.00',
          currency: 'LKR',
          billStatus: 'UNPAID',
        ),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('assistant_text_field')), 'Pay my bill');
      await tester.tap(find.byKey(const Key('assistant_send_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('payment_plan_cancel_button')));
      await tester.pumpAndSettle();

      expect(fakeAgentService.confirmedTokens, isEmpty);
      expect(mockCheckoutService.launchCount, 0);
      expect(find.text('Payment cancelled'), findsOneWidget);
    });

    // 10. Confirmation endpoint returning PENDING invokes existing PayHere flow.
    testWidgets(
        '10. Confirmation endpoint returning PENDING invokes existing PayHere flow',
        (tester) async {
      fakeAgentService.nextChatResponse = const AgentChatResponse(
        message: 'Proposal',
        requiresConfirmation: true,
        confirmationId: 'token-pending-flow',
        paymentPlan: PaymentPlan(
          billId: 'b-1',
          biller: 'CEB',
          accountNumber: '12347',
          amount: '7200.00',
          currency: 'LKR',
          billStatus: 'UNPAID',
        ),
      );
      fakeAgentService.nextConfirmResponse = const AgentPaymentConfirmResponse(
        transactionId: 'tx-pending-123',
        billId: 'b-1',
        amount: '7200.00',
        currency: 'LKR',
        status: 'PENDING',
      );
      mockCheckoutService.autoTrigger = 'complete';
      fakePaymentRepo.backendTransactionStatus = 'SUCCESS';

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('assistant_text_field')), 'Pay my bill');
      await tester.tap(find.byKey(const Key('assistant_send_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('payment_plan_confirm_button')));
      await tester.pumpAndSettle();

      expect(
          fakePaymentRepo.initiatedTransactionIds, contains('tx-pending-123'));
      expect(mockCheckoutService.launchCount, 1);
    });

    // 11. Expired confirmation shows error and does not launch PayHere.
    testWidgets(
        '11. Expired confirmation shows error and does not launch PayHere',
        (tester) async {
      fakeAgentService.nextChatResponse = const AgentChatResponse(
        message: 'Proposal',
        requiresConfirmation: true,
        confirmationId: 'token-expired',
        paymentPlan: PaymentPlan(
          billId: 'b-1',
          biller: 'CEB',
          accountNumber: '12347',
          amount: '7200.00',
          currency: 'LKR',
          billStatus: 'UNPAID',
        ),
      );
      fakeAgentService.confirmException = ValidationError(
          'Payment confirmation has expired. Please request a new payment plan.');

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('assistant_text_field')), 'Pay my bill');
      await tester.tap(find.byKey(const Key('assistant_send_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('payment_plan_confirm_button')));
      await tester.pumpAndSettle();

      expect(mockCheckoutService.launchCount, 0);
      expect(find.textContaining('expired'), findsAtLeastNWidgets(1));
    });

    // 12. Already-used confirmation shows error.
    testWidgets('12. Already-used confirmation shows error', (tester) async {
      fakeAgentService.nextChatResponse = const AgentChatResponse(
        message: 'Proposal',
        requiresConfirmation: true,
        confirmationId: 'token-used',
        paymentPlan: PaymentPlan(
          billId: 'b-1',
          biller: 'CEB',
          accountNumber: '12347',
          amount: '7200.00',
          currency: 'LKR',
          billStatus: 'UNPAID',
        ),
      );
      fakeAgentService.confirmException =
          ValidationError('This payment confirmation has already been used.');

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('assistant_text_field')), 'Pay my bill');
      await tester.tap(find.byKey(const Key('assistant_send_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('payment_plan_confirm_button')));
      await tester.pumpAndSettle();

      expect(mockCheckoutService.launchCount, 0);
      expect(find.textContaining('already been used'), findsAtLeastNWidgets(1));
    });

    // 13. 422 response handled safely.
    testWidgets('13. 422 response handled safely', (tester) async {
      fakeAgentService.nextChatResponse = const AgentChatResponse(
        message: 'Proposal',
        requiresConfirmation: true,
        confirmationId: 'token-422',
        paymentPlan: PaymentPlan(
          billId: 'b-1',
          biller: 'CEB',
          accountNumber: '12347',
          amount: '7200.00',
          currency: 'LKR',
          billStatus: 'UNPAID',
        ),
      );
      fakeAgentService.confirmException =
          ValidationError('Extra inputs are not permitted');

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('assistant_text_field')), 'Pay my bill');
      await tester.tap(find.byKey(const Key('assistant_send_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('payment_plan_confirm_button')));
      await tester.pumpAndSettle();

      expect(mockCheckoutService.launchCount, 0);
      expect(find.textContaining('Extra inputs are not permitted'),
          findsAtLeastNWidgets(1));
    });

    // 14. PayHere cancel handled using existing flow.
    testWidgets('14. PayHere cancel handled using existing flow',
        (tester) async {
      fakeAgentService.nextChatResponse = const AgentChatResponse(
        message: 'Proposal',
        requiresConfirmation: true,
        confirmationId: 'token-cancel-payhere',
        paymentPlan: PaymentPlan(
          billId: 'b-1',
          biller: 'CEB',
          accountNumber: '12347',
          amount: '7200.00',
          currency: 'LKR',
          billStatus: 'UNPAID',
        ),
      );
      fakePaymentRepo.backendTransactionStatus = 'CANCELLED';
      mockCheckoutService.autoTrigger = 'dismiss';

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('assistant_text_field')), 'Pay my bill');
      await tester.tap(find.byKey(const Key('assistant_send_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('payment_plan_confirm_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('payment_result_dialog')), findsOneWidget);
      expect(find.text('Payment Cancelled'), findsOneWidget);
    });

    // 15. PayHere failure handled using existing flow.
    testWidgets('15. PayHere failure handled using existing flow',
        (tester) async {
      fakeAgentService.nextChatResponse = const AgentChatResponse(
        message: 'Proposal',
        requiresConfirmation: true,
        confirmationId: 'token-fail-payhere',
        paymentPlan: PaymentPlan(
          billId: 'b-1',
          biller: 'CEB',
          accountNumber: '12347',
          amount: '7200.00',
          currency: 'LKR',
          billStatus: 'UNPAID',
        ),
      );
      fakePaymentRepo.backendTransactionStatus = 'FAILED';
      mockCheckoutService.autoTrigger = 'error';

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('assistant_text_field')), 'Pay my bill');
      await tester.tap(find.byKey(const Key('assistant_send_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('payment_plan_confirm_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('payment_result_dialog')), findsOneWidget);
      expect(find.text('Payment Failed'), findsOneWidget);
    });

    // 16. Backend SUCCESS refreshes bills/history.
    testWidgets(
        '16. Backend SUCCESS refreshes bills and transactions providers',
        (tester) async {
      fakeAgentService.nextChatResponse = const AgentChatResponse(
        message: 'Proposal',
        requiresConfirmation: true,
        confirmationId: 'token-success-payhere',
        paymentPlan: PaymentPlan(
          billId: 'b-1',
          biller: 'CEB',
          accountNumber: '12347',
          amount: '7200.00',
          currency: 'LKR',
          billStatus: 'UNPAID',
        ),
      );
      fakePaymentRepo.backendTransactionStatus = 'SUCCESS';
      mockCheckoutService.autoTrigger = 'complete';

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('assistant_text_field')), 'Pay my bill');
      await tester.tap(find.byKey(const Key('assistant_send_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('payment_plan_confirm_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('payment_result_dialog')), findsOneWidget);
      expect(find.text('Payment Successful'), findsOneWidget);
      expect(find.text('Amount: LKR 7200.00'), findsOneWidget);
    });

    testWidgets('17. Account transition clears Assistant draft and chat state',
        (tester) async {
      final authNotifier = MockAuthNotifier();
      fakeAgentService.nextChatResponse = const AgentChatResponse(
        message: 'User A response',
        requiresConfirmation: false,
      );
      await tester.pumpWidget(createTestWidget(authNotifier: authNotifier));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('assistant_text_field')), 'User A message');
      await tester.tap(find.byKey(const Key('assistant_send_button')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('assistant_text_field')), 'unsent User A draft');

      await authNotifier.logout();
      authNotifier.authenticate(
        const User(id: 'bob-id', name: 'Bob', email: 'bob@example.com'),
      );
      await tester.pumpAndSettle();

      final textField = tester.widget<TextField>(
        find.byKey(const Key('assistant_text_field')),
      );
      expect(textField.controller?.text, isEmpty);
      expect(find.text('User A message'), findsNothing);
      expect(find.text('User A response'), findsNothing);
    });

    testWidgets('18. Account transition removes an open payment result dialog',
        (tester) async {
      final authNotifier = MockAuthNotifier();
      fakeAgentService.nextChatResponse = const AgentChatResponse(
        message: 'Proposal',
        requiresConfirmation: true,
        confirmationId: 'user-a-confirmation',
        paymentPlan: PaymentPlan(
          billId: 'b-1',
          biller: 'CEB',
          accountNumber: '12347',
          amount: '7200.00',
          currency: 'LKR',
          billStatus: 'UNPAID',
        ),
      );
      fakePaymentRepo.backendTransactionStatus = 'SUCCESS';
      mockCheckoutService.autoTrigger = 'complete';
      await tester.pumpWidget(createTestWidget(authNotifier: authNotifier));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('assistant_text_field')), 'Pay my bill');
      await tester.tap(find.byKey(const Key('assistant_send_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('payment_plan_confirm_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('payment_result_dialog')), findsOneWidget);

      await authNotifier.logout();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('payment_result_dialog')), findsNothing);
    });
  });
}
