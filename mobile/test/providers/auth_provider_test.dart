import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';

import 'package:mobile/services/api_client.dart';
import 'package:mobile/core/storage/token_storage.dart';
import 'package:mobile/repositories/auth_repository.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/models/auth_state.dart';
import '../core/token_storage_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  group('AuthProvider', () {
    late MockFlutterSecureStorage mockStorage;
    late TokenStorage tokenStorage;

    setUp(() {
      mockStorage = MockFlutterSecureStorage();
      tokenStorage = TokenStorage(storage: mockStorage);
    });

    test('startup with no token sets unauthenticated state', () async {
      final mockClient = MockClient((request) async => http.Response('{}', 200));
      final apiClient = ApiClient(client: mockClient);
      final repo = AuthRepository(apiClient: apiClient, tokenStorage: tokenStorage);

      final notifier = AuthNotifier(
        repository: repo,
        tokenStorage: tokenStorage,
        apiClient: apiClient,
      );

      await Future.delayed(Duration.zero);
      expect(notifier.state.status, AuthStatus.unauthenticated);
    });

    test('startup with valid token calls /auth/me and sets authenticated state', () async {
      await tokenStorage.saveToken('valid_token');

      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/auth/me')) {
          expect(request.headers['Authorization'], 'Bearer valid_token');
          return http.Response(
            jsonEncode({
              'id': 'u-100',
              'name': 'Existing User',
              'email': 'existing@example.com',
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final apiClient = ApiClient(client: mockClient);
      final repo = AuthRepository(apiClient: apiClient, tokenStorage: tokenStorage);

      final notifier = AuthNotifier(
        repository: repo,
        tokenStorage: tokenStorage,
        apiClient: apiClient,
      );

      await Future.delayed(Duration.zero);
      expect(notifier.state.status, AuthStatus.authenticated);
      expect(notifier.state.user?.name, 'Existing User');
    });

    test('startup with invalid token deletes token and sets unauthenticated state', () async {
      await tokenStorage.saveToken('invalid_token');

      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'detail': 'Invalid token'}), 401);
      });

      final apiClient = ApiClient(client: mockClient);
      final repo = AuthRepository(apiClient: apiClient, tokenStorage: tokenStorage);

      final notifier = AuthNotifier(
        repository: repo,
        tokenStorage: tokenStorage,
        apiClient: apiClient,
      );

      await Future.delayed(Duration.zero);
      expect(notifier.state.status, AuthStatus.unauthenticated);
      expect(await tokenStorage.getToken(), isNull);
    });

    test('login sets authenticated state directly from response', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'access_token': 'new_login_token',
            'token_type': 'bearer',
            'user': {
              'id': 'u-200',
              'name': 'Logged In User',
              'email': 'login@example.com',
            }
          }),
          200,
        );
      });

      final apiClient = ApiClient(client: mockClient);
      final repo = AuthRepository(apiClient: apiClient, tokenStorage: tokenStorage);

      final notifier = AuthNotifier(
        repository: repo,
        tokenStorage: tokenStorage,
        apiClient: apiClient,
      );

      await Future.delayed(Duration.zero);
      await notifier.login('login@example.com', 'pass123');

      expect(notifier.state.status, AuthStatus.authenticated);
      expect(notifier.state.user?.email, 'login@example.com');
    });
  });
}
