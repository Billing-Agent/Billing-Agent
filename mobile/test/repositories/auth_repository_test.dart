import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';

import 'package:mobile/services/api_client.dart';
import 'package:mobile/core/storage/token_storage.dart';
import 'package:mobile/core/errors/app_errors.dart';
import 'package:mobile/repositories/auth_repository.dart';
import '../core/token_storage_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  group('AuthRepository', () {
    late MockFlutterSecureStorage mockStorage;
    late TokenStorage tokenStorage;

    setUp(() {
      mockStorage = MockFlutterSecureStorage();
      tokenStorage = TokenStorage(storage: mockStorage);
    });

    test('login succeeds with token-only response, saves token, and fetches current user', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/auth/login')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['email'], 'test@example.com');
          expect(body['password'], 'password123');
          return http.Response(
            jsonEncode({
              'access_token': 'jwt_secret_token',
              'token_type': 'bearer',
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/auth/me')) {
          expect(request.headers['Authorization'], 'Bearer jwt_secret_token');
          return http.Response(
            jsonEncode({
              'id': 'u-1',
              'name': 'Test User',
              'email': 'test@example.com',
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(client: mockClient);
      final repo = AuthRepository(apiClient: apiClient, tokenStorage: tokenStorage);

      final authResponse = await repo.login('test@example.com', 'password123');

      expect(authResponse.accessToken, 'jwt_secret_token');
      expect(authResponse.tokenType, 'bearer');
      expect(authResponse.user, isNotNull);
      expect(authResponse.user!.id, 'u-1');
      expect(authResponse.user!.name, 'Test User');
      expect(authResponse.user!.email, 'test@example.com');
      expect(await tokenStorage.getToken(), 'jwt_secret_token');
    });

    test('login with invalid credentials throws UnauthorizedError and cleans up token', () async {
      await tokenStorage.saveToken('stale_token');

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'Invalid email or password'}),
          401,
        );
      });

      final apiClient = ApiClient(client: mockClient);
      apiClient.setToken('stale_token');
      final repo = AuthRepository(apiClient: apiClient, tokenStorage: tokenStorage);

      try {
        await repo.login('test@example.com', 'wrong_password');
        fail('Should have thrown UnauthorizedError');
      } catch (e) {
        expect(e, isA<UnauthorizedError>());
      }

      // Verify token cleanup occurred
      expect(await tokenStorage.getToken(), isNull);
    });

    test('login current-user lookup failure cleans up persisted token and throws', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/auth/login')) {
          return http.Response(
            jsonEncode({
              'access_token': 'jwt_temp_token',
              'token_type': 'bearer',
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/auth/me')) {
          return http.Response(
            jsonEncode({'detail': 'Internal Server Error'}),
            500,
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(client: mockClient);
      final repo = AuthRepository(apiClient: apiClient, tokenStorage: tokenStorage);

      try {
        await repo.login('test@example.com', 'password123');
        fail('Should have thrown ServerError');
      } catch (e) {
        expect(e, isA<ServerError>());
      }

      // Verify token storage was cleaned up after the failure
      expect(await tokenStorage.getToken(), isNull);
    });

    test('login with empty access token throws ServerError and cleans up', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'access_token': '',
            'token_type': 'bearer',
          }),
          200,
        );
      });

      final apiClient = ApiClient(client: mockClient);
      final repo = AuthRepository(apiClient: apiClient, tokenStorage: tokenStorage);

      try {
        await repo.login('test@example.com', 'password123');
        fail('Should have thrown ServerError');
      } catch (e) {
        expect(e, isA<ServerError>());
      }

      expect(await tokenStorage.getToken(), isNull);
    });

    test('register succeeds with user response without token and does not save token', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, endsWith('/auth/register'));
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['name'], 'New User');
        expect(body['email'], 'new@example.com');
        expect(body['password'], 'password123');
        return http.Response(
          jsonEncode({
            'id': 'u-2',
            'name': 'New User',
            'email': 'new@example.com',
            'phone': null,
            'is_active': true,
            'created_at': '2026-01-01T00:00:00Z',
            'updated_at': '2026-01-01T00:00:00Z',
          }),
          201,
        );
      });

      final apiClient = ApiClient(client: mockClient);
      final repo = AuthRepository(apiClient: apiClient, tokenStorage: tokenStorage);

      final user = await repo.register(
        name: 'New User',
        email: 'new@example.com',
        password: 'password123',
      );

      expect(user.id, 'u-2');
      expect(user.name, 'New User');
      expect(user.email, 'new@example.com');
      // Registration response has no token, so tokenStorage must not have saved anything
      expect(await tokenStorage.getToken(), isNull);
    });

    test('getCurrentUser fetches profile via /auth/me', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, endsWith('/auth/me'));
        return http.Response(
          jsonEncode({
            'id': 'u-1',
            'name': 'Current User',
            'email': 'current@example.com',
          }),
          200,
        );
      });

      final apiClient = ApiClient(client: mockClient);
      final repo = AuthRepository(apiClient: apiClient, tokenStorage: tokenStorage);

      final user = await repo.getCurrentUser();
      expect(user.id, 'u-1');
      expect(user.name, 'Current User');
    });

    test('logout clears stored token', () async {
      await tokenStorage.saveToken('token_to_clear');

      final mockClient = MockClient((request) async => http.Response('', 200));
      final apiClient = ApiClient(client: mockClient);
      apiClient.setToken('token_to_clear');
      final repo = AuthRepository(apiClient: apiClient, tokenStorage: tokenStorage);

      await repo.logout();

      expect(await tokenStorage.getToken(), isNull);
    });
  });
}
