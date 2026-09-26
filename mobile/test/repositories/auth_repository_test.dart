import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';

import 'package:mobile/services/api_client.dart';
import 'package:mobile/core/storage/token_storage.dart';
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

    test('login succeeds and saves token', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, endsWith('/auth/login'));
        return http.Response(
          jsonEncode({
            'access_token': 'jwt_secret_token',
            'token_type': 'bearer',
            'user': {
              'id': 'u-1',
              'name': 'Test User',
              'email': 'test@example.com',
            }
          }),
          200,
        );
      });

      final apiClient = ApiClient(client: mockClient);
      final repo = AuthRepository(apiClient: apiClient, tokenStorage: tokenStorage);

      final authResponse = await repo.login('test@example.com', 'password123');

      expect(authResponse.accessToken, 'jwt_secret_token');
      expect(authResponse.user.email, 'test@example.com');
      expect(await tokenStorage.getToken(), 'jwt_secret_token');
    });

    test('register succeeds and saves token', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, endsWith('/auth/register'));
        return http.Response(
          jsonEncode({
            'access_token': 'jwt_new_user_token',
            'token_type': 'bearer',
            'user': {
              'id': 'u-2',
              'name': 'New User',
              'email': 'new@example.com',
            }
          }),
          200,
        );
      });

      final apiClient = ApiClient(client: mockClient);
      final repo = AuthRepository(apiClient: apiClient, tokenStorage: tokenStorage);

      final authResponse = await repo.register(
        name: 'New User',
        email: 'new@example.com',
        password: 'password123',
      );

      expect(authResponse.accessToken, 'jwt_new_user_token');
      expect(authResponse.user.name, 'New User');
      expect(await tokenStorage.getToken(), 'jwt_new_user_token');
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
