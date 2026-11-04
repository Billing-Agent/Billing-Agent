import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/core/errors/app_errors.dart';
import 'package:mobile/repositories/agent_repository.dart';
import 'package:mobile/services/api_client.dart';

void main() {
  group('AgentRepository Tests', () {
    test('sendMessage sends POST /agent/chat with user message', () async {
      String? capturedPath;
      Map<String, dynamic>? capturedBody;

      final mockClient = MockClient((request) async {
        capturedPath = request.url.path;
        capturedBody = jsonDecode(request.body);

        final responseJson = {
          'message': 'You have 1 unpaid bill.',
          'intent': 'VIEW_BILLS',
          'requires_confirmation': false,
          'payment_plan': null,
          'confirmation_id': null,
        };
        return http.Response(jsonEncode(responseJson), 200);
      });

      final apiClient = ApiClient(client: mockClient);
      final repo = AgentRepository(apiClient);

      final res = await repo.sendMessage('Show my bills');

      expect(capturedPath, endsWith('/agent/chat'));
      expect(capturedBody, {'message': 'Show my bills'});
      expect(res.message, 'You have 1 unpaid bill.');
      expect(res.requiresConfirmation, isFalse);
    });

    test('confirmPayment sends ONLY confirmation_id in request body', () async {
      String? capturedPath;
      Map<String, dynamic>? capturedBody;

      final mockClient = MockClient((request) async {
        capturedPath = request.url.path;
        capturedBody = jsonDecode(request.body);

        final responseJson = {
          'transaction_id': '66c9c31d-d6c6-4a94-a5fe-044988cd9cd6',
          'bill_id': '1acb2cc9-b988-4106-88e9-4e84e077fc2e',
          'amount': '7200.00',
          'currency': 'LKR',
          'status': 'PENDING',
        };
        return http.Response(jsonEncode(responseJson), 200);
      });

      final apiClient = ApiClient(client: mockClient);
      final repo = AgentRepository(apiClient);

      final res = await repo.confirmPayment('valid-conf-uuid-1234');

      expect(capturedPath, endsWith('/agent/payments/confirm'));
      // CRITICAL: Request payload MUST have ONLY confirmation_id
      expect(capturedBody, isNotNull);
      expect(capturedBody!.keys.length, 1);
      expect(capturedBody!['confirmation_id'], 'valid-conf-uuid-1234');
      expect(capturedBody!.containsKey('amount'), isFalse);
      expect(capturedBody!.containsKey('user_id'), isFalse);
      expect(capturedBody!.containsKey('bill_id'), isFalse);
      expect(capturedBody!.containsKey('payment_method_id'), isFalse);
      expect(capturedBody!.containsKey('currency'), isFalse);

      expect(res.transactionId, '66c9c31d-d6c6-4a94-a5fe-044988cd9cd6');
      expect(res.status, 'PENDING');
      expect(res.amount, '7200.00');
    });

    test('confirmPayment throws ValidationError when confirmation has expired or already used', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'This payment confirmation has already been used.'}),
          400,
        );
      });

      final apiClient = ApiClient(client: mockClient);
      final repo = AgentRepository(apiClient);

      expect(
        () => repo.confirmPayment('used-token'),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            contains('already been used'),
          ),
        ),
      );
    });

    test('confirmPayment throws ValidationError on 422 extra field response', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'detail': [
              {
                'type': 'extra_forbidden',
                'loc': ['body', 'amount'],
                'msg': 'Extra inputs are not permitted',
              }
            ]
          }),
          422,
        );
      });

      final apiClient = ApiClient(client: mockClient);
      final repo = AgentRepository(apiClient);

      expect(
        () => repo.confirmPayment('extra-field-token'),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.message,
            'message',
            contains('Extra inputs are not permitted'),
          ),
        ),
      );
    });
  });
}
