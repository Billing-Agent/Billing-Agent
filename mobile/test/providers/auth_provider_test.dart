import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';

import 'package:mobile/services/api_client.dart';
import 'package:mobile/core/storage/token_storage.dart';
import 'package:mobile/core/errors/app_errors.dart';
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

    test('login succeeds: parses token-only response, fetches user via /auth/me, and sets authenticated state', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/auth/login')) {
          return http.Response(
            jsonEncode({
              'access_token': 'new_login_token',
              'token_type': 'bearer',
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/auth/me')) {
          expect(request.headers['Authorization'], 'Bearer new_login_token');
          return http.Response(
            jsonEncode({
              'id': 'u-200',
              'name': 'Logged In User',
              'email': 'login@example.com',
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
      await notifier.login('login@example.com', 'pass123');

      expect(notifier.state.status, AuthStatus.authenticated);
      expect(notifier.state.user?.email, 'login@example.com');
      expect(notifier.state.user?.name, 'Logged In User');
      expect(await tokenStorage.getToken(), 'new_login_token');
    });

    test('login with invalid credentials sets unauthenticated state and cleans up token', () async {
      await tokenStorage.saveToken('stale_token');

      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/auth/login')) {
          return http.Response(
            jsonEncode({'detail': 'Invalid email or password'}),
            401,
          );
        }
        return http.Response('Not found', 404);
      });

      final apiClient = ApiClient(client: mockClient);
      apiClient.setToken('stale_token');
      final repo = AuthRepository(apiClient: apiClient, tokenStorage: tokenStorage);

      final notifier = AuthNotifier(
        repository: repo,
        tokenStorage: tokenStorage,
        apiClient: apiClient,
      );

      await Future.delayed(Duration.zero);

      try {
        await notifier.login('bad@example.com', 'wrong_pass');
        fail('Should have thrown UnauthorizedError');
      } catch (e) {
        expect(e, isA<UnauthorizedError>());
      }

      expect(notifier.state.status, AuthStatus.unauthenticated);
      expect(notifier.state.errorMessage, isNotNull);
      expect(await tokenStorage.getToken(), isNull);
    });

    test('login failure during current-user lookup leaves app unauthenticated and cleans up token', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/auth/login')) {
          return http.Response(
            jsonEncode({
              'access_token': 'new_login_token',
              'token_type': 'bearer',
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/auth/me')) {
          return http.Response(
            jsonEncode({'detail': 'User not found or inactive'}),
            401,
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

      try {
        await notifier.login('login@example.com', 'pass123');
        fail('Should have thrown UnauthorizedError');
      } catch (e) {
        expect(e, isA<UnauthorizedError>());
      }

      expect(notifier.state.status, AuthStatus.unauthenticated);
      expect(await tokenStorage.getToken(), isNull);
    });

    test('successful registration followed by login sets authenticated state', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/auth/register')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['name'], 'Registered User');
          expect(body['email'], 'reg@example.com');
          expect(body['password'], 'secret123');
          // Backend returns HTTP 201 with UserResponse without access_token
          return http.Response(
            jsonEncode({
              'id': 'u-300',
              'name': 'Registered User',
              'email': 'reg@example.com',
              'phone': null,
              'is_active': true,
              'created_at': '2026-01-01T00:00:00Z',
              'updated_at': '2026-01-01T00:00:00Z',
            }),
            201,
          );
        }
        if (request.url.path.endsWith('/auth/login')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['email'], 'reg@example.com');
          expect(body['password'], 'secret123');
          return http.Response(
            jsonEncode({
              'access_token': 'jwt_reg_token',
              'token_type': 'bearer',
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/auth/me')) {
          expect(request.headers['Authorization'], 'Bearer jwt_reg_token');
          return http.Response(
            jsonEncode({
              'id': 'u-300',
              'name': 'Registered User',
              'email': 'reg@example.com',
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
      await notifier.register('Registered User', 'reg@example.com', 'secret123');

      expect(notifier.state.status, AuthStatus.authenticated);
      expect(notifier.state.user?.name, 'Registered User');
      expect(notifier.state.user?.email, 'reg@example.com');
      expect(await tokenStorage.getToken(), 'jwt_reg_token');
    });

    test('registration failure sets unauthenticated state and cleans up token', () async {
      await tokenStorage.saveToken('stale_token');

      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/auth/register')) {
          return http.Response(
            jsonEncode({'detail': 'Email already registered'}),
            400,
          );
        }
        return http.Response('Not found', 404);
      });

      final apiClient = ApiClient(client: mockClient);
      apiClient.setToken('stale_token');
      final repo = AuthRepository(apiClient: apiClient, tokenStorage: tokenStorage);

      final notifier = AuthNotifier(
        repository: repo,
        tokenStorage: tokenStorage,
        apiClient: apiClient,
      );

      await Future.delayed(Duration.zero);

      try {
        await notifier.register('Bad User', 'existing@example.com', 'secret123');
        fail('Should have thrown ValidationError');
      } catch (e) {
        expect(e, isA<ValidationError>());
      }

      expect(notifier.state.status, AuthStatus.unauthenticated);
      expect(notifier.state.errorMessage, isNotNull);
      expect(await tokenStorage.getToken(), isNull);
    });

    test('registration succeeds but subsequent login fails sets unauthenticated state and clears token', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/auth/register')) {
          return http.Response(
            jsonEncode({
              'id': 'u-300',
              'name': 'New User',
              'email': 'new@example.com',
            }),
            201,
          );
        }
        if (request.url.path.endsWith('/auth/login')) {
          return http.Response(
            jsonEncode({'detail': 'Invalid email or password'}),
            401,
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

      try {
        await notifier.register('New User', 'new@example.com', 'secret123');
        fail('Should have thrown UnauthorizedError');
      } catch (e) {
        expect(e, isA<UnauthorizedError>());
      }

      expect(notifier.state.status, AuthStatus.unauthenticated);
      expect(await tokenStorage.getToken(), isNull);
    });

    test('logout sets unauthenticated state and clears stored token', () async {
      await tokenStorage.saveToken('active_token');

      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/auth/me')) {
          return http.Response(
            jsonEncode({
              'id': 'u-1',
              'name': 'Active User',
              'email': 'active@example.com',
            }),
            200,
          );
        }
        return http.Response('', 200);
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

      await notifier.logout();

      expect(notifier.state.status, AuthStatus.unauthenticated);
      expect(await tokenStorage.getToken(), isNull);
    });

    test('handleUnauthorized logs out if currently authenticated', () async {
      await tokenStorage.saveToken('active_token');

      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/auth/me')) {
          return http.Response(
            jsonEncode({
              'id': 'u-1',
              'name': 'Active User',
              'email': 'active@example.com',
            }),
            200,
          );
        }
        return http.Response('', 200);
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

      await notifier.handleUnauthorized();

      expect(notifier.state.status, AuthStatus.unauthenticated);
      expect(await tokenStorage.getToken(), isNull);
    });
  });
}
