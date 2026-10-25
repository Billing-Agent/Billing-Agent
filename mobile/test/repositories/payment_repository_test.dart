import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';

import 'package:mobile/services/api_client.dart';
import 'package:mobile/repositories/payment_repository.dart';

void main() {
  group('PaymentRepository', () {
    test('getUserPaymentMethods requests GET /me/payment-methods with Bearer token and no x-user-id', () async {
      String? requestedPath;
      Map<String, String>? headers;

      final mockClient = MockClient((request) async {
        requestedPath = request.url.path;
        headers = request.headers;
        return http.Response(
          jsonEncode([
            {
              'id': 'pm-1',
              'provider': 'STRIPE',
              'card_brand': 'VISA',
              'last_four': '4242',
              'is_default': true,
            }
          ]),
          200,
        );
      });

      final apiClient = ApiClient(client: mockClient);
      apiClient.setToken('auth_token');
      final repo = PaymentRepository(apiClient);

      final methods = await repo.getUserPaymentMethods();

      expect(requestedPath, endsWith('/me/payment-methods'));
      expect(headers?['Authorization'], 'Bearer auth_token');
      expect(headers?.containsKey('x-user-id'), isFalse);
      expect(methods.length, 1);
      expect(methods.first.id, 'pm-1');
      expect(methods.first.tokenReference, isNull);
    });

    test('getUserTransactions requests GET /me/transactions', () async {
      String? requestedPath;
      final mockClient = MockClient((request) async {
        requestedPath = request.url.path;
        return http.Response(
          jsonEncode([
            {
              'id': 'tx-100',
              'biller': 'CEB',
              'amount': '1500.00',
              'currency': 'LKR',
              'status': 'SUCCESS',
              'created_at': '2026-10-12T10:00:00Z',
            }
          ]),
          200,
        );
      });

      final apiClient = ApiClient(client: mockClient);
      final repo = PaymentRepository(apiClient);

      final txs = await repo.getUserTransactions();

      expect(requestedPath, endsWith('/me/transactions'));
      expect(txs.length, 1);
      expect(txs.first.id, 'tx-100');
      expect(txs.first.status, 'SUCCESS');
    });

    test('getPaymentStatus requests GET /payments/{transaction_id}', () async {
      String? requestedPath;
      final mockClient = MockClient((request) async {
        requestedPath = request.url.path;
        return http.Response(
          jsonEncode({
            'id': 'tx-200',
            'biller': 'Water Board',
            'amount': '500.00',
            'currency': 'LKR',
            'status': 'SUCCESS',
            'created_at': '2026-10-12T11:00:00Z',
          }),
          200,
        );
      });

      final apiClient = ApiClient(client: mockClient);
      final repo = PaymentRepository(apiClient);

      final tx = await repo.getPaymentStatus('tx-200');

      expect(requestedPath, endsWith('/payments/tx-200'));
      expect(tx, isNotNull);
      expect(tx?.id, 'tx-200');
      expect(tx?.status, 'SUCCESS');
    });

    test('repeating preparePayment with same idempotency key succeeds without creating a second transaction', () async {
      int callCount = 0;
      String? endpoint;
      
      final mockClient = MockClient((request) async {
        callCount++;
        endpoint = request.url.path;
        // The mock backend returns the same transaction ID both times
        return http.Response(jsonEncode({
          'transaction_id': '12345678-1234-1234-1234-123456789012',
          'bill_id': '00000000-0000-0000-0000-000000000000',
          'amount': '1000.00',
          'currency': 'LKR',
          'status': 'PENDING'
        }), 200);
      });

      final apiClient = ApiClient(client: mockClient);
      final repo = PaymentRepository(apiClient);

      final tx1 = await repo.preparePayment('bill1', 'pm1', 'idem-key-1');
      final tx2 = await repo.preparePayment('bill1', 'pm1', 'idem-key-1');

      expect(endpoint, endsWith('/payments/prepare'));
      expect(callCount, 2);
      expect(tx1.id, tx2.id); // Same transaction ID returned
      expect(tx1.amount, tx2.amount);
    });

    test('initiatePayment requests POST /payments/{transaction_id}/initiate with Bearer token, no body, and parses response', () async {
      String? requestedPath;
      String? requestedMethod;
      String? requestBody;
      Map<String, String>? headers;

      final mockClient = MockClient((request) async {
        requestedPath = request.url.path;
        requestedMethod = request.method;
        requestBody = request.body;
        headers = request.headers;
        return http.Response(
          jsonEncode({
            'merchant_id': '1211149',
            'order_id': 'tx-init-123',
            'items': 'CEB Bill',
            'currency': 'LKR',
            'amount': '1500.00',
            'first_name': 'Dev',
            'last_name': 'User',
            'email': 'dev@example.com',
            'phone': '+94771234567',
            'address': 'Main St',
            'city': 'Colombo',
            'country': 'Sri Lanka',
            'return_url': 'http://localhost/return',
            'cancel_url': 'http://localhost/cancel',
            'notify_url': 'http://localhost/notify',
            'hash': 'ABC123MD5HASH',
          }),
          200,
        );
      });

      final apiClient = ApiClient(client: mockClient);
      apiClient.setToken('bearer_jwt_token_123');
      final repo = PaymentRepository(apiClient);

      final initiateResp = await repo.initiatePayment('tx-init-123');

      expect(requestedMethod, 'POST');
      expect(requestedPath, endsWith('/payments/tx-init-123/initiate'));
      expect(headers?['Authorization'], 'Bearer bearer_jwt_token_123');
      // No request body is sent
      expect(requestBody, isEmpty);
      expect(initiateResp.orderId, 'tx-init-123');
      expect(initiateResp.merchantId, '1211149');
      expect(initiateResp.hash, 'ABC123MD5HASH');
      expect(initiateResp.amount, '1500.00');
    });
  });
}
