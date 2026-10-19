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
import 'package:mobile/screens/auth/register_screen.dart';
import '../core/token_storage_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  testWidgets('RegisterScreen renders fields and validates empty inputs', (WidgetTester tester) async {
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
          home: RegisterScreen(),
        ),
      ),
    );

    expect(find.byKey(const Key('register_name_field')), findsOneWidget);
    expect(find.byKey(const Key('register_email_field')), findsOneWidget);
    expect(find.byKey(const Key('register_password_field')), findsOneWidget);
    expect(find.byKey(const Key('register_confirm_password_field')), findsOneWidget);
    expect(find.byKey(const Key('register_button')), findsOneWidget);

    // Tap register without filling fields
    await tester.tap(find.byKey(const Key('register_button')));
    await tester.pumpAndSettle();

    expect(find.text('Please enter your full name'), findsOneWidget);
    expect(find.text('Please enter your email'), findsOneWidget);
    expect(find.text('Please enter a password'), findsOneWidget);
  });

  testWidgets('RegisterScreen validates password mismatch', (WidgetTester tester) async {
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
          home: RegisterScreen(),
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('register_name_field')), 'Test User');
    await tester.enterText(find.byKey(const Key('register_email_field')), 'test@example.com');
    await tester.enterText(find.byKey(const Key('register_password_field')), 'secret123');
    await tester.enterText(find.byKey(const Key('register_confirm_password_field')), 'different123');
    await tester.tap(find.byKey(const Key('register_button')));
    await tester.pumpAndSettle();

    expect(find.text('Passwords do not match'), findsOneWidget);
  });

  testWidgets('RegisterScreen submits form successfully with backend 201 contract', (WidgetTester tester) async {
    final mockStorage = MockFlutterSecureStorage();
    final tokenStorage = TokenStorage(storage: mockStorage);

    final mockClient = MockClient((request) async {
      if (request.url.path.endsWith('/auth/register')) {
        return http.Response(
          jsonEncode({
            'id': 'u-reg-1',
            'name': 'Widget Register User',
            'email': 'widgetreg@example.com',
            'phone': null,
            'is_active': true,
          }),
          201,
        );
      }
      if (request.url.path.endsWith('/auth/login')) {
        return http.Response(
          jsonEncode({
            'access_token': 'reg_token',
            'token_type': 'bearer',
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/auth/me')) {
        return http.Response(
          jsonEncode({
            'id': 'u-reg-1',
            'name': 'Widget Register User',
            'email': 'widgetreg@example.com',
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
          home: RegisterScreen(),
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('register_name_field')), 'Widget Register User');
    await tester.enterText(find.byKey(const Key('register_email_field')), 'widgetreg@example.com');
    await tester.enterText(find.byKey(const Key('register_password_field')), 'password123');
    await tester.enterText(find.byKey(const Key('register_confirm_password_field')), 'password123');

    await tester.tap(find.byKey(const Key('register_button')));
    await tester.pumpAndSettle();

    expect(find.text('Please enter your full name'), findsNothing);
    expect(find.text('Passwords do not match'), findsNothing);
  });
}
