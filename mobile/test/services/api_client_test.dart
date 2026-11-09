import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:async';
import 'dart:convert';

import 'package:mobile/services/api_client.dart';
import 'package:mobile/core/storage/token_storage.dart';
import 'package:mobile/core/errors/app_errors.dart';
import '../core/token_storage_test.dart';

class DelayedTokenStorage extends TokenStorage {
  DelayedTokenStorage() : super(storage: MockFlutterSecureStorage());

  final readStarted = Completer<void>();
  final storedToken = Completer<String?>();

  @override
  Future<String?> getToken() {
    readStarted.complete();
    return storedToken.future;
  }
}

void main() {
  group('ApiClient', () {
    test('returns data on 200 response', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'data': 'success'}), 200);
      });

      final apiClient = ApiClient(client: mockClient);
      final response = await apiClient.get('/test');

      expect(response, isNotNull);
      expect(response['data'], 'success');
    });

    test(
        'includes Authorization Bearer header and NO x-user-id header when token is set',
        () async {
      Map<String, String>? capturedHeaders;
      final mockClient = MockClient((request) async {
        capturedHeaders = request.headers;
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      });

      final apiClient = ApiClient(client: mockClient);
      apiClient.setToken('test_jwt_token');
      await apiClient.get('/test');

      expect(capturedHeaders?['Authorization'], 'Bearer test_jwt_token');
      expect(capturedHeaders?.containsKey('x-user-id'), isFalse);
      expect(capturedHeaders?.containsKey('X-User-Id'), isFalse);

      apiClient.clearToken();
      await apiClient.get('/test');
      expect(capturedHeaders?['Authorization'], isNull);
    });

    test(
        'resolves token from TokenStorage automatically if in-memory token is unset',
        () async {
      final mockStorage = MockFlutterSecureStorage();
      final tokenStorage = TokenStorage(storage: mockStorage);
      await tokenStorage.saveToken('stored_jwt_token');

      String? authHeader;
      final mockClient = MockClient((request) async {
        authHeader = request.headers['Authorization'];
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      });

      final apiClient =
          ApiClient(client: mockClient, tokenStorage: tokenStorage);
      await apiClient.get('/me/bills');

      expect(authHeader, 'Bearer stored_jwt_token');
    });

    test('does not overwrite a newer session with a delayed storage read',
        () async {
      final tokenStorage = DelayedTokenStorage();
      String? authHeader;
      final mockClient = MockClient((request) async {
        authHeader = request.headers['Authorization'];
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      });
      final apiClient = ApiClient(
        client: mockClient,
        tokenStorage: tokenStorage,
      );

      final request = apiClient.get('/me/bills');
      await tokenStorage.readStarted.future;
      apiClient.setToken('user-b-token');
      tokenStorage.storedToken.complete('user-a-token');
      await request;

      expect(authHeader, 'Bearer user-b-token');
    });

    test('invokes onUnauthorized callback on 401 for protected endpoints',
        () async {
      bool unauthorizedCallbackInvoked = false;
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'detail': 'Token expired'}), 401);
      });

      final apiClient = ApiClient(
        client: mockClient,
        onUnauthorized: () {
          unauthorizedCallbackInvoked = true;
        },
      );

      try {
        await apiClient.get('/me/bills');
        fail('Should have thrown UnauthorizedError');
      } catch (e) {
        expect(e, isA<UnauthorizedError>());
      }
      expect(unauthorizedCallbackInvoked, isTrue);
    });

    test('does not log out a newer session when an older request returns 401',
        () async {
      final responseCompleter = Completer<http.Response>();
      final requestStarted = Completer<void>();
      bool unauthorizedCallbackInvoked = false;
      final mockClient = MockClient((request) {
        requestStarted.complete();
        return responseCompleter.future;
      });
      final apiClient = ApiClient(
        client: mockClient,
        onUnauthorized: () {
          unauthorizedCallbackInvoked = true;
        },
      );

      apiClient.setToken('user-a-token');
      final oldRequest = apiClient.get('/me/bills');
      await requestStarted.future;

      apiClient.clearToken();
      apiClient.setToken('user-b-token');
      responseCompleter.complete(
        http.Response(jsonEncode({'detail': 'User A token expired'}), 401),
      );

      await expectLater(oldRequest, throwsA(isA<UnauthorizedError>()));
      expect(unauthorizedCallbackInvoked, isFalse);
    });

    test(
        'does NOT invoke onUnauthorized callback on 401 for /auth/login or /auth/register',
        () async {
      bool unauthorizedCallbackInvoked = false;
      final mockClient = MockClient((request) async {
        return http.Response(
            jsonEncode({'detail': 'Invalid credentials'}), 401);
      });

      final apiClient = ApiClient(
        client: mockClient,
        onUnauthorized: () {
          unauthorizedCallbackInvoked = true;
        },
      );

      try {
        await apiClient
            .post('/auth/login', data: {'email': 'a@b.com', 'password': 'pw'});
        fail('Should have thrown UnauthorizedError');
      } catch (e) {
        expect(e, isA<UnauthorizedError>());
      }
      expect(unauthorizedCallbackInvoked, isFalse);
    });

    test('throws ValidationError on 400', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'detail': 'Bad request data'}), 400);
      });

      final apiClient = ApiClient(client: mockClient);

      expect(() => apiClient.post('/test', data: {}),
          throwsA(isA<ValidationError>()));
    });

    test('throws NetworkError on 404', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'detail': 'Not found'}), 404);
      });

      final apiClient = ApiClient(client: mockClient);

      expect(() => apiClient.get('/test'), throwsA(isA<NetworkError>()));
    });

    test('throws ServerError on 409', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'detail': 'Conflict'}), 409);
      });

      final apiClient = ApiClient(client: mockClient);

      expect(
          () => apiClient.post('/test', data: {}), throwsA(isA<ServerError>()));
    });
  });
}
