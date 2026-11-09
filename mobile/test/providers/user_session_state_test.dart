import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/storage/token_storage.dart';
import 'package:mobile/models/agent_response.dart';
import 'package:mobile/models/auth_state.dart';
import 'package:mobile/models/bill.dart';
import 'package:mobile/models/payhere_initiate.dart';
import 'package:mobile/models/payment_method.dart';
import 'package:mobile/models/payment_plan.dart';
import 'package:mobile/models/transaction.dart';
import 'package:mobile/models/user.dart';
import 'package:mobile/providers/agent_provider.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/repositories/auth_repository.dart';
import 'package:mobile/repositories/bill_repository.dart';
import 'package:mobile/repositories/payment_repository.dart';
import 'package:mobile/repositories/providers.dart';
import 'package:mobile/services/agent_service.dart';
import 'package:mobile/services/api_client.dart';
import 'package:mobile/services/payhere_checkout_service.dart';

import '../core/token_storage_test.dart';

class MutableAuthNotifier extends AuthNotifier {
  MutableAuthNotifier(User user)
      : super(
          repository: AuthRepository(
            apiClient: ApiClient(),
            tokenStorage: TokenStorage(storage: MockFlutterSecureStorage()),
          ),
          tokenStorage: TokenStorage(storage: MockFlutterSecureStorage()),
          apiClient: ApiClient(),
        ) {
    state = AuthState.authenticated(user);
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

class SessionBillRepository implements BillRepository {
  String account = 'A';
  int billsCallCount = 0;
  Completer<List<Bill>>? pendingBills;

  Bill get bill => Bill(
        id: '$account-bill',
        biller: '$account Power',
        accountNumber: '$account-001',
        amountDue: '100.00',
        currency: 'LKR',
        status: 'UNPAID',
        dueDate: null,
      );

  @override
  Future<List<Bill>> getUserBills() {
    billsCallCount++;
    final pending = pendingBills;
    pendingBills = null;
    return pending?.future ?? Future.value([bill]);
  }

  @override
  Future<Bill?> getBillById(String id) async => bill;
}

class SessionPaymentRepository implements PaymentRepository {
  String account = 'A';
  int initiateCount = 0;
  int statusCount = 0;

  PaymentMethod get method => PaymentMethod(
        id: '$account-method',
        provider: 'PAYHERE',
        isDefault: true,
      );

  Transaction get transaction => Transaction(
        id: '$account-transaction',
        biller: '$account Power',
        amount: '100.00',
        currency: 'LKR',
        status: 'PENDING',
        createdAt: DateTime(2026, 11, 9),
      );

  @override
  Future<List<PaymentMethod>> getUserPaymentMethods() async => [method];

  @override
  Future<List<Transaction>> getUserTransactions() async => [transaction];

  @override
  Future<Transaction?> getPaymentStatus(String transactionId) async {
    statusCount++;
    return transaction;
  }

  @override
  Future<Transaction> preparePayment(
    String billId,
    String paymentMethodId,
    String idempotencyKey,
  ) async =>
      transaction;

  @override
  Future<PayHereInitiateResponse> initiatePayment(String transactionId) async {
    initiateCount++;
    return PayHereInitiateResponse(
      merchantId: 'test-merchant',
      orderId: transactionId,
      items: 'Test bill',
      currency: 'LKR',
      amount: '100.00',
      firstName: account,
      lastName: 'User',
      email: '${account.toLowerCase()}@example.com',
      phone: '+94770000000',
      address: 'Test address',
      city: 'Colombo',
      country: 'Sri Lanka',
      returnUrl: 'https://example.com/return',
      cancelUrl: 'https://example.com/cancel',
      notifyUrl: 'https://example.com/notify',
      hash: 'test-hash',
    );
  }
}

class SessionAgentService implements AgentService {
  String account = 'A';
  Completer<AgentChatResponse>? pendingResponse;
  Completer<AgentPaymentConfirmResponse>? pendingConfirmation;
  AgentChatResponse? nextResponse;

  @override
  Future<AgentChatResponse> sendMessage(String message) {
    final pending = pendingResponse;
    pendingResponse = null;
    if (pending != null) return pending.future;

    final response = nextResponse;
    nextResponse = null;
    return Future.value(
      response ??
          AgentChatResponse(
            message: '$account assistant response',
            requiresConfirmation: false,
          ),
    );
  }

  @override
  Future<AgentPaymentConfirmResponse> confirmPayment(String confirmationId) {
    final pending = pendingConfirmation;
    pendingConfirmation = null;
    return pending?.future ??
        Future.value(
          const AgentPaymentConfirmResponse(
            transactionId: 'A-transaction',
            billId: 'A-bill',
            amount: '100.00',
            currency: 'LKR',
            status: 'PENDING',
          ),
        );
  }
}

class SessionCheckoutService implements PayHereCheckoutService {
  int launchCount = 0;
  void Function(String paymentId)? onCompleted;

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
    this.onCompleted = onCompleted;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const userA = User(id: 'user-a', name: 'User A', email: 'a@example.com');
  const userB = User(id: 'user-b', name: 'User B', email: 'b@example.com');

  late MutableAuthNotifier authNotifier;
  late SessionBillRepository billRepository;
  late SessionPaymentRepository paymentRepository;
  late SessionAgentService agentService;
  late SessionCheckoutService checkoutService;
  late ProviderContainer container;

  setUp(() {
    authNotifier = MutableAuthNotifier(userA);
    billRepository = SessionBillRepository();
    paymentRepository = SessionPaymentRepository();
    agentService = SessionAgentService();
    checkoutService = SessionCheckoutService();
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((ref) => authNotifier),
        billRepositoryProvider.overrideWithValue(billRepository),
        paymentRepositoryProvider.overrideWithValue(paymentRepository),
        agentServiceProvider.overrideWithValue(agentService),
        payHereCheckoutServiceProvider.overrideWithValue(checkoutService),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  Future<void> warmUserScopedState() async {
    await container.read(userBillsProvider.future);
    await container.read(billDetailsProvider('shared-bill').future);
    await container.read(userPaymentMethodsProvider.future);
    await container.read(userTransactionsProvider.future);
    await container.read(paymentStatusProvider('shared-transaction').future);
    await container
        .read(agentChatProvider.notifier)
        .sendMessage('show my account');
  }

  test('logout clears every user-scoped provider and Assistant state',
      () async {
    await warmUserScopedState();

    expect(container.read(userBillsProvider).value?.single.id, 'A-bill');
    expect(container.read(agentChatProvider).messages, isNotEmpty);

    await authNotifier.logout();

    expect(await container.read(userBillsProvider.future), isEmpty);
    expect(await container.read(billDetailsProvider('shared-bill').future),
        isNull);
    expect(await container.read(userPaymentMethodsProvider.future), isEmpty);
    expect(await container.read(userTransactionsProvider.future), isEmpty);
    expect(
      await container.read(paymentStatusProvider('shared-transaction').future),
      isNull,
    );
    expect(container.read(agentChatProvider).messages, isEmpty);
    expect(container.read(agentChatProvider).activeConfirmationId, isNull);
    expect(container.read(agentChatProvider).isConfirming, isFalse);
  });

  test('User A state and late results cannot reach User B session', () async {
    await warmUserScopedState();

    final delayedBills = Completer<List<Bill>>();
    billRepository.pendingBills = delayedBills;
    container.invalidate(userBillsProvider);
    final oldBillsFuture = container.read(userBillsProvider.future);

    final delayedAgent = Completer<AgentChatResponse>();
    agentService.pendingResponse = delayedAgent;
    final oldAgentFuture = container
        .read(agentChatProvider.notifier)
        .sendMessage('delayed A request');

    await authNotifier.logout();
    billRepository.account = 'B';
    paymentRepository.account = 'B';
    agentService.account = 'B';
    authNotifier.authenticate(userB);

    delayedBills
        .complete([billRepository.bill.copyWithForTest(id: 'A-late-bill')]);
    delayedAgent.complete(
      const AgentChatResponse(
        message: 'A late assistant response',
        requiresConfirmation: false,
      ),
    );
    await oldAgentFuture;
    expect(await oldBillsFuture, isEmpty);

    expect(
        (await container.read(userBillsProvider.future)).single.id, 'B-bill');
    expect(
      (await container.read(billDetailsProvider('shared-bill').future))?.id,
      'B-bill',
    );
    expect(
      (await container.read(userPaymentMethodsProvider.future)).single.id,
      'B-method',
    );
    expect(
      (await container.read(userTransactionsProvider.future)).single.id,
      'B-transaction',
    );
    expect(
      (await container.read(paymentStatusProvider('shared-transaction').future))
          ?.id,
      'B-transaction',
    );
    expect(container.read(agentChatProvider).messages, isEmpty);

    await container.read(agentChatProvider.notifier).sendMessage('B request');
    final messages = container.read(agentChatProvider).messages;
    expect(messages.map((message) => message.text),
        contains('B assistant response'));
    expect(messages.map((message) => message.text),
        isNot(contains('A assistant response')));
    expect(messages.map((message) => message.text),
        isNot(contains('A late assistant response')));
  });

  test('same authenticated session keeps normal cache and Assistant continuity',
      () async {
    final firstBills = await container.read(userBillsProvider.future);
    final secondBills = await container.read(userBillsProvider.future);

    expect(firstBills.single.id, 'A-bill');
    expect(secondBills.single.id, 'A-bill');
    expect(billRepository.billsCallCount, 1);

    await container.read(agentChatProvider.notifier).sendMessage('first');
    await container.read(agentChatProvider.notifier).sendMessage('second');

    final messages = container.read(agentChatProvider).messages;
    expect(messages.length, 4);
    expect(messages.map((message) => message.text),
        contains('A assistant response'));
  });

  test('same-account logout and login creates a new isolated session',
      () async {
    await warmUserScopedState();
    final oldSession = container.read(authenticatedSessionProvider)!;

    await authNotifier.logout();
    authNotifier.authenticate(userA);
    final newSession = container.read(authenticatedSessionProvider)!;

    expect(oldSession.isActive, isFalse);
    expect(identical(oldSession, newSession), isFalse);
    expect(container.read(agentChatProvider).messages, isEmpty);
    expect(
        (await container.read(userBillsProvider.future)).single.id, 'A-bill');
  });

  test(
      'delayed Assistant confirmation cannot initiate payment after account switch',
      () async {
    agentService.nextResponse = const AgentChatResponse(
      message: 'A payment plan',
      requiresConfirmation: true,
      confirmationId: 'A-confirmation',
      paymentPlan: PaymentPlan(
        billId: 'A-bill',
        biller: 'A Power',
        accountNumber: 'A-001',
        amount: '100.00',
        currency: 'LKR',
        billStatus: 'UNPAID',
      ),
    );
    await container.read(agentChatProvider.notifier).sendMessage('pay A bill');
    final planMessage = container.read(agentChatProvider).messages.last;
    final delayedConfirmation = Completer<AgentPaymentConfirmResponse>();
    agentService.pendingConfirmation = delayedConfirmation;
    final paymentResults = <String>[];

    final confirmation =
        container.read(agentChatProvider.notifier).confirmPaymentPlan(
              messageId: planMessage.id,
              confirmationId: planMessage.confirmationId!,
              onPaymentResult: ({
                required status,
                required title,
                required transactionId,
                required amount,
                required currency,
                message,
              }) {
                paymentResults.add(status);
              },
            );

    await authNotifier.logout();
    authNotifier.authenticate(userB);
    delayedConfirmation.complete(
      const AgentPaymentConfirmResponse(
        transactionId: 'A-transaction',
        billId: 'A-bill',
        amount: '100.00',
        currency: 'LKR',
        status: 'PENDING',
      ),
    );
    await confirmation;

    expect(paymentRepository.initiateCount, 0);
    expect(checkoutService.launchCount, 0);
    expect(paymentResults, isEmpty);
    expect(container.read(agentChatProvider).messages, isEmpty);
  });

  test('late Assistant SDK callback cannot poll or update a new account',
      () async {
    agentService.nextResponse = const AgentChatResponse(
      message: 'A payment plan',
      requiresConfirmation: true,
      confirmationId: 'A-confirmation',
      paymentPlan: PaymentPlan(
        billId: 'A-bill',
        biller: 'A Power',
        accountNumber: 'A-001',
        amount: '100.00',
        currency: 'LKR',
        billStatus: 'UNPAID',
      ),
    );
    await container.read(agentChatProvider.notifier).sendMessage('pay A bill');
    final planMessage = container.read(agentChatProvider).messages.last;
    final paymentResults = <String>[];

    await container.read(agentChatProvider.notifier).confirmPaymentPlan(
          messageId: planMessage.id,
          confirmationId: planMessage.confirmationId!,
          onPaymentResult: ({
            required status,
            required title,
            required transactionId,
            required amount,
            required currency,
            message,
          }) {
            paymentResults.add(status);
          },
        );
    expect(checkoutService.launchCount, 1);

    await authNotifier.logout();
    authNotifier.authenticate(userB);
    checkoutService.onCompleted?.call('late-A-provider-result');
    await Future<void>.delayed(Duration.zero);

    expect(paymentRepository.statusCount, 0);
    expect(paymentResults, isEmpty);
    expect(container.read(agentChatProvider).messages, isEmpty);
  });
}

extension on Bill {
  Bill copyWithForTest({required String id}) {
    return Bill(
      id: id,
      biller: biller,
      accountNumber: accountNumber,
      amountDue: amountDue,
      currency: currency,
      status: status,
      dueDate: dueDate,
    );
  }
}
