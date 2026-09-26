import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';

import 'package:mobile/services/api_client.dart';
import 'package:mobile/core/errors/app_errors.dart';

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

    test('includes Authorization Bearer header when token is set', () async {
      String? authHeader;
      final mockClient = MockClient((request) async {
        authHeader = request.headers['Authorization'];
        return http.Response(jsonEncode({'status': 'ok'}), 200);
      });

      final apiClient = ApiClient(client: mockClient);
      apiClient.setToken('test_jwt_token');
      await apiClient.get('/test');

      expect(authHeader, 'Bearer test_jwt_token');

      apiClient.clearToken();
      await apiClient.get('/test');
      expect(authHeader, isNull);
    });

    test('throws UnauthorizedError on 401 response code', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'detail': 'Token expired'}), 401);
      });

      final apiClient = ApiClient(client: mockClient);
      expect(() => apiClient.get('/protected'), throwsA(isA<UnauthorizedError>()));
    });

    test('throws ValidationError on 400', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'detail': 'Bad request data'}), 400);
      });

      final apiClient = ApiClient(client: mockClient);

      expect(() => apiClient.post('/test', data: {}), throwsA(isA<ValidationError>()));
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

      expect(() => apiClient.post('/test', data: {}), throwsA(isA<ServerError>()));
    });
  });
}
