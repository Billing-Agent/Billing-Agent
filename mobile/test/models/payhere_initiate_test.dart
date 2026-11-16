import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/payhere_initiate.dart';

void main() {
  group('PayHereInitiateResponse', () {
    final sampleJson = {
      'merchant_id': '1211149',
      'order_id': 'f7d2f9d2-9bc5-4424-9bdf-992a6c8e3e44',
      'items': 'CEB Electricity Bill',
      'currency': 'LKR',
      'amount': '1500.00',
      'first_name': 'Dev',
      'last_name': 'User',
      'email': 'dev@example.com',
      'phone': '+94771234567',
      'address': 'No. 1, Main Street',
      'city': 'Colombo',
      'country': 'Sri Lanka',
      'return_url': 'http://localhost:8000/api/v1/payhere/return',
      'cancel_url': 'http://localhost:8000/api/v1/payhere/cancel',
      'notify_url': 'http://localhost:8000/api/v1/payhere/callback',
      'hash': '4E723829C157E6D7DF38AC5812FE4EBA',
    };

    test(
        'parses all fields from backend initiate response including hash and redirect urls',
        () {
      final response = PayHereInitiateResponse.fromMap(sampleJson);

      expect(response.merchantId, '1211149');
      expect(response.orderId, 'f7d2f9d2-9bc5-4424-9bdf-992a6c8e3e44');
      expect(response.items, 'CEB Electricity Bill');
      expect(response.currency, 'LKR');
      expect(response.amount, '1500.00');
      expect(response.firstName, 'Dev');
      expect(response.lastName, 'User');
      expect(response.email, 'dev@example.com');
      expect(response.phone, '+94771234567');
      expect(response.address, 'No. 1, Main Street');
      expect(response.city, 'Colombo');
      expect(response.country, 'Sri Lanka');
      expect(response.returnUrl, 'http://localhost:8000/api/v1/payhere/return');
      expect(response.cancelUrl, 'http://localhost:8000/api/v1/payhere/cancel');
      expect(
          response.notifyUrl, 'http://localhost:8000/api/v1/payhere/callback');
      expect(response.hash, '4E723829C157E6D7DF38AC5812FE4EBA');
    });

    test('toPaymentObject contains only pinned native SDK checkout fields', () {
      final response = PayHereInitiateResponse.fromMap(sampleJson);
      final paymentObj = response.toPaymentObject(sandbox: true);

      expect(paymentObj['sandbox'], isTrue);
      expect(paymentObj['merchant_id'], '1211149');
      expect(paymentObj['order_id'], 'f7d2f9d2-9bc5-4424-9bdf-992a6c8e3e44');
      expect(paymentObj['amount'], '1500.00');
      expect(paymentObj['currency'], 'LKR');
      expect(paymentObj['notify_url'],
          'http://localhost:8000/api/v1/payhere/callback');

      // The Flutter Mobile SDK must NOT use web-checkout redirect/hash parameters
      expect(paymentObj.containsKey('hash'), isFalse);
      expect(paymentObj.containsKey('return_url'), isFalse);
      expect(paymentObj.containsKey('cancel_url'), isFalse);
      expect(paymentObj.containsKey('merchant_secret'), isFalse);
      expect(paymentObj.containsKey('payhere_secret'), isFalse);

      expect(
          paymentObj.keys,
          unorderedEquals([
            'sandbox',
            'merchant_id',
            'notify_url',
            'order_id',
            'items',
            'amount',
            'currency',
            'first_name',
            'last_name',
            'email',
            'phone',
            'address',
            'city',
            'country',
          ]));
    });

    test('toMap converts back to map preserving backend snake_case format', () {
      final response = PayHereInitiateResponse.fromMap(sampleJson);
      final map = response.toMap();

      expect(map['merchant_id'], '1211149');
      expect(map['order_id'], 'f7d2f9d2-9bc5-4424-9bdf-992a6c8e3e44');
      expect(map['amount'], '1500.00');
      expect(map['hash'], '4E723829C157E6D7DF38AC5812FE4EBA');
    });

    test('equality and hashCode work as expected', () {
      final resp1 = PayHereInitiateResponse.fromMap(sampleJson);
      final resp2 = PayHereInitiateResponse.fromMap(sampleJson);

      expect(resp1, equals(resp2));
      expect(resp1.hashCode, equals(resp2.hashCode));
    });
  });
}
