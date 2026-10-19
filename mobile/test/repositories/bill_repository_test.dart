import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';

import 'package:mobile/services/api_client.dart';
import 'package:mobile/repositories/bill_repository.dart';

void main() {
  group('BillRepository', () {
    test('getUserBills requests GET /me/bills and injects Bearer token with no x-user-id', () async {
      String? requestedPath;
      Map<String, String>? headers;

      final mockClient = MockClient((request) async {
        requestedPath = request.url.path;
        headers = request.headers;

        return http.Response(
          jsonEncode([
            {
              'id': 'bill-1',
              'biller': 'CEB',
              'account_number': '12345',
              'amount_due': '1500.00',
              'currency': 'LKR',
              'status': 'UNPAID',
              'due_date': '2026-10-30T00:00:00Z',
            }
          ]),
          200,
        );
      });

      final apiClient = ApiClient(client: mockClient);
      apiClient.setToken('my_jwt_token');
      final repo = BillRepository(apiClient);

      final bills = await repo.getUserBills();

      expect(requestedPath, endsWith('/me/bills'));
      expect(headers?['Authorization'], 'Bearer my_jwt_token');
      expect(headers?.containsKey('x-user-id'), isFalse);
      expect(headers?.containsKey('X-User-Id'), isFalse);
      expect(bills.length, 1);
      expect(bills.first.id, 'bill-1');
      expect(bills.first.biller, 'CEB');
    });

    test('getBillById requests GET /bills/{id}', () async {
      String? requestedPath;

      final mockClient = MockClient((request) async {
        requestedPath = request.url.path;
        return http.Response(
          jsonEncode({
            'id': 'bill-42',
            'biller': 'Water Board',
            'account_number': '98765',
            'amount_due': '750.00',
            'currency': 'LKR',
            'status': 'UNPAID',
            'due_date': '2026-11-15T00:00:00Z',
          }),
          200,
        );
      });

      final apiClient = ApiClient(client: mockClient);
      final repo = BillRepository(apiClient);

      final bill = await repo.getBillById('bill-42');

      expect(requestedPath, endsWith('/bills/bill-42'));
      expect(bill, isNotNull);
      expect(bill?.id, 'bill-42');
      expect(bill?.amountDue, '750.00');
    });
  });
}
