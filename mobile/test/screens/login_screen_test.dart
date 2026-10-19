import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';

import 'package:mobile/services/api_client.dart';
import 'package:mobile/repositories/bill_repository.dart';
import 'package:mobile/core/storage/token_storage.dart';
import 'package:mobile/repositories/auth_repository.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/screens/auth/login_screen.dart';
import '../core/token_storage_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  testWidgets('LoginScreen renders fields and validates empty inputs', (WidgetTester tester) async {
    final mockStorage = MockFlutterSecureStorage();
    final tokenStorage = TokenStorage(storage: mockStorage);
    final mockClient = MockClient((request) async => http.Response('{}', 200));
    final apiClient = ApiClient(client: mockClient);
    final authRepo = AuthRepository(apiClient: apiClient, tokenStorage: tokenStorage);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(tokenStorage),
          apiClientProvider.overrideWithValue(apiClient),
          authRepositoryProvider.overrideWithValue(authRepo),
        ],
        child: const MaterialApp(
          home: LoginScreen(),
        ),
      ),
    );

    expect(find.byKey(const Key('login_email_field')), findsOneWidget);
    expect(find.byKey(const Key('login_password_field')), findsOneWidget);
    expect(find.byKey(const Key('login_button')), findsOneWidget);

    // Tap login button without filling fields
    await tester.tap(find.byKey(const Key('login_button')));
    await tester.pumpAndSettle();

    expect(find.text('Please enter your email'), findsOneWidget);
    expect(find.text('Please enter your password'), findsOneWidget);
  });

  testWidgets('LoginScreen submits form with valid credentials', (WidgetTester tester) async {
    final mockStorage = MockFlutterSecureStorage();
    final tokenStorage = TokenStorage(storage: mockStorage);
    
    final mockClient = MockClient((request) async {
      if (request.url.path.endsWith('/auth/login')) {
        return http.Response(
          jsonEncode({
            'access_token': 'test_token',
            'token_type': 'bearer',
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/auth/me')) {
        return http.Response(
          jsonEncode({
            'id': 'u-1',
            'name': 'Widget Test User',
            'email': 'widget@example.com',
          }),
          200,
        );
      }
      return http.Response('Not Found', 404);
    });
    
    final apiClient = ApiClient(client: mockClient);
    final authRepo = AuthRepository(apiClient: apiClient, tokenStorage: tokenStorage);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStorageProvider.overrideWithValue(tokenStorage),
          apiClientProvider.overrideWithValue(apiClient),
          authRepositoryProvider.overrideWithValue(authRepo),
        ],
        child: const MaterialApp(
          home: LoginScreen(),
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('login_email_field')), 'widget@example.com');
    await tester.enterText(find.byKey(const Key('login_password_field')), 'secret123');
    await tester.tap(find.byKey(const Key('login_button')));
    await tester.pumpAndSettle();

    expect(find.text('Please enter your email'), findsNothing);
    expect(find.text('Please enter your password'), findsNothing);
  });
}
