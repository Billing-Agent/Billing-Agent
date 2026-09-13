import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:convert';

import 'package:mobile/services/api_client.dart';
import 'package:mobile/repositories/payment_repository.dart';

void main() {
  group('PaymentRepository', () {
    test('repeating preparePayment with same idempotency key succeeds without creating a second transaction', () async {
      int callCount = 0;
      
      final mockClient = MockClient((request) async {
        callCount++;
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

      expect(callCount, 2);
      expect(tx1.id, tx2.id); // Same transaction ID returned
      expect(tx1.amount, tx2.amount);
    });
  });
}
