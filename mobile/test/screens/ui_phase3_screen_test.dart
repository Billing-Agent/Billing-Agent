import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/storage/token_storage.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/models/auth_state.dart';
import 'package:mobile/models/bill.dart';
import 'package:mobile/models/transaction.dart';
import 'package:mobile/models/user.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/repositories/auth_repository.dart';
import 'package:mobile/repositories/bill_repository.dart';
import 'package:mobile/repositories/payment_repository.dart';
import 'package:mobile/screens/bill_details/bill_details_screen.dart';
import 'package:mobile/screens/settings/settings_screen.dart';
import 'package:mobile/screens/transactions/transactions_screen.dart';
import 'package:mobile/services/api_client.dart';
import 'package:mobile/widgets/bill_card.dart';
import 'package:mobile/widgets/transaction_card.dart';

import '../core/token_storage_test.dart';

class _FakeBillRepository extends BillRepository {
  final Bill bill;

  _FakeBillRepository(this.bill) : super(ApiClient());

  @override
  Future<Bill?> getBillById(String id) async => bill;
}

class _FailingPaymentRepository extends PaymentRepository {
  _FailingPaymentRepository() : super(ApiClient());

  @override
  Future<List<Transaction>> getUserTransactions() async {
    throw Exception('sensitive transport details');
  }
}

class _SettingsAuthNotifier extends AuthNotifier {
  int logoutCount = 0;

  _SettingsAuthNotifier()
      : super(
          repository: AuthRepository(
            apiClient: ApiClient(),
            tokenStorage: TokenStorage(storage: MockFlutterSecureStorage()),
          ),
          tokenStorage: TokenStorage(storage: MockFlutterSecureStorage()),
          apiClient: ApiClient(),
        ) {
    state = AuthState.authenticated(
      const User(
        id: 'settings-user',
        name: 'Portfolio User',
        email: 'portfolio@example.com',
      ),
    );
  }

  @override
  Future<void> checkAuthStatus() async {}

  @override
  Future<void> logout() async {
    logoutCount++;
    state = AuthState.unauthenticated();
  }
}

void main() {
  const unpaidBill = Bill(
    id: 'bill-unpaid',
    biller: 'A very long electricity provider name for responsive testing',
    accountNumber: '123456789',
    amountDue: '7200.00',
    currency: 'LKR',
    status: 'UNPAID',
    dueDate: null,
  );

  testWidgets('bill and transaction cards remain private and scannable',
      (tester) async {
    final shortAccountBill = Bill(
      id: 'bill-short',
      biller: 'Water Board',
      accountNumber: '1234',
      amountDue: '500.00',
      currency: 'LKR',
      status: 'PAID',
      dueDate: DateTime(2026, 12, 31),
    );
    final pendingTransaction = Transaction(
      id: 'transaction-reference-123456789',
      biller: 'Water Board',
      amount: '500.00',
      currency: 'LKR',
      status: 'PENDING',
      createdAt: DateTime(2026, 11, 18),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 900),
              textScaler: TextScaler.linear(1.3),
            ),
            child: SizedBox(
              width: 320,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    BillCard(bill: shortAccountBill),
                    TransactionCard(transaction: pendingTransaction),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Account ••••'), findsOneWidget);
    expect(find.text('1234'), findsNothing);
    expect(find.text('PAID'), findsOneWidget);
    expect(find.text('PENDING'), findsOneWidget);
    expect(
      find.text('Payment is awaiting final status confirmation.'),
      findsOneWidget,
    );
    expect(find.text('transaction-reference-123456789'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bill details preserve nullable date and UNPAID payment gate',
      (tester) async {
    Bill? routedBill;
    final router = GoRouter(
      initialLocation: '/bill',
      routes: [
        GoRoute(
          path: '/bill',
          builder: (context, state) =>
              const BillDetailsScreen(initialBill: unpaidBill),
        ),
        GoRoute(
          path: '/payment-confirmation',
          builder: (context, state) {
            routedBill = state.extra as Bill?;
            return const Scaffold(body: Text('Payment destination'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authenticatedSessionProvider.overrideWithValue(
            AuthenticatedSession('user-a'),
          ),
          billRepositoryProvider.overrideWithValue(
            _FakeBillRepository(unpaidBill),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.lightTheme,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('LKR 7,200.00'), findsOneWidget);
    expect(find.text('UNPAID'), findsOneWidget);
    expect(find.text('•••• 6789'), findsOneWidget);
    expect(find.text('123456789'), findsNothing);
    expect(find.text('Not available'), findsOneWidget);
    expect(
      find.byKey(const Key('bill_details_payment_button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('bill_details_payment_button')));
    await tester.pumpAndSettle();

    expect(find.text('Payment destination'), findsOneWidget);
    expect(identical(routedBill, unpaidBill), isTrue);
  });

  testWidgets('paid bill details do not expose payment CTA', (tester) async {
    final paidBill = Bill(
      id: 'bill-paid',
      biller: 'Water Board',
      accountNumber: '987654321',
      amountDue: '0.00',
      currency: 'LKR',
      status: 'PAID',
      dueDate: DateTime(2026, 10, 1),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authenticatedSessionProvider.overrideWithValue(
            AuthenticatedSession('user-a'),
          ),
          billRepositoryProvider.overrideWithValue(
            _FakeBillRepository(paidBill),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: BillDetailsScreen(initialBill: paidBill),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PAID'), findsOneWidget);
    expect(
      find.byKey(const Key('bill_details_payment_button')),
      findsNothing,
    );
  });

  testWidgets('transaction screen hides raw unexpected errors', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authenticatedSessionProvider.overrideWithValue(
            AuthenticatedSession('user-a'),
          ),
          paymentRepositoryProvider.overrideWithValue(
            _FailingPaymentRepository(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const TransactionsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Failed to load transactions.'), findsOneWidget);
    expect(find.textContaining('sensitive transport details'), findsNothing);
  });

  testWidgets('settings placeholders are disabled and logout remains active',
      (tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authNotifier = _SettingsAuthNotifier();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authProvider.overrideWith((ref) => authNotifier)],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final profileTile = tester.widget<ListTile>(
      find.byKey(const Key('settings_profile_item')),
    );
    final paymentMethodsTile = tester.widget<ListTile>(
      find.byKey(const Key('settings_payment_methods_item')),
    );
    final notificationsTile = tester.widget<ListTile>(
      find.byKey(const Key('settings_notifications_item')),
    );
    final securityTile = tester.widget<ListTile>(
      find.byKey(const Key('settings_security_item')),
    );
    expect(profileTile.enabled, isFalse);
    expect(profileTile.onTap, isNull);
    expect(paymentMethodsTile.enabled, isFalse);
    expect(paymentMethodsTile.onTap, isNull);
    expect(notificationsTile.enabled, isFalse);
    expect(notificationsTile.onTap, isNull);
    expect(securityTile.enabled, isFalse);
    expect(securityTile.onTap, isNull);
    expect(find.text('Coming soon'), findsWidgets);

    await tester.tap(find.byKey(const Key('logout_button')));
    await tester.pumpAndSettle();

    expect(authNotifier.logoutCount, 1);
  });
}
