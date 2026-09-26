import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';

import 'package:mobile/main.dart';
import 'package:mobile/widgets/state_views.dart';
import 'package:mobile/repositories/bill_repository.dart';
import 'package:mobile/services/api_client.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/repositories/auth_repository.dart';
import 'package:mobile/core/storage/token_storage.dart';
import 'package:mobile/models/auth_state.dart';
import 'package:mobile/models/user.dart';
import 'core/token_storage_test.dart';

class MockAuthNotifier extends AuthNotifier {
  MockAuthNotifier(AuthState initialState)
      : super(
          repository: AuthRepository(
            apiClient: ApiClient(),
            tokenStorage: TokenStorage(storage: MockFlutterSecureStorage()),
          ),
          tokenStorage: TokenStorage(storage: MockFlutterSecureStorage()),
          apiClient: ApiClient(),
        ) {
    state = initialState;
  }

  @override
  Future<void> checkAuthStatus() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  const testUser = User(
    id: '11111111-1111-1111-1111-111111111111',
    name: 'Dev User',
    email: 'dev@example.com',
  );

  // Create a mock API client that returns dummy bills
  final mockClient = MockClient((request) async {
    if (request.url.path.contains('/bills')) {
      return http.Response(jsonEncode([
        {
          'id': '0000-0000-0000-0001',
          'user_id': '11111111-1111-1111-1111-111111111111',
          'biller': 'CEB',
          'account_number': '123456789',
          'amount_due': '1500.00',
          'currency': 'LKR',
          'status': 'UNPAID',
          'due_date': '2023-12-31T00:00:00Z',
          'created_at': '2023-01-01T00:00:00Z',
          'updated_at': '2023-01-01T00:00:00Z',
        },
        {
          'id': '0000-0000-0000-0002',
          'user_id': '11111111-1111-1111-1111-111111111111',
          'biller': 'WATER',
          'account_number': '987654321',
          'amount_due': '800.00',
          'currency': 'LKR',
          'status': 'UNPAID',
          'due_date': '2023-12-31T00:00:00Z',
          'created_at': '2023-01-01T00:00:00Z',
          'updated_at': '2023-01-01T00:00:00Z',
        }
      ]), 200);
    }
    return http.Response('Not Found', 404);
  });

  final mockApiClient = ApiClient(client: mockClient);

  testWidgets('App starts successfully and renders Home screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(mockApiClient),
          authProvider.overrideWith((ref) => MockAuthNotifier(AuthState.authenticated(testUser))),
        ],
        child: const BillingAgentApp(),
      ),
    );
    await tester.pumpAndSettle(); // wait for animations and futures

    // Verify that the home screen is displayed
    expect(find.text('Billing Agent'), findsOneWidget);
    expect(find.text('Good morning, Dev User'), findsOneWidget);
    expect(find.text('Upcoming Bills'), findsOneWidget);
    
    // Look for CEB bill in upcoming bills
    expect(find.text('CEB'), findsWidgets);
  });

  testWidgets('Bottom navigation works and renders Bills screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(mockApiClient),
          authProvider.overrideWith((ref) => MockAuthNotifier(AuthState.authenticated(testUser))),
        ],
        child: const BillingAgentApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Tap on the Bills tab
    await tester.tap(find.byIcon(Icons.receipt_long_outlined).first);
    await tester.pumpAndSettle();

    // Verify Bills screen
    expect(find.text('My Bills'), findsOneWidget);
    
    // Look for both CEB and WATER bills
    expect(find.text('CEB'), findsWidgets);
    expect(find.text('WATER'), findsWidgets);
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
