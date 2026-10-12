import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/payment_method.dart';

void main() {
  group('PaymentMethod Model', () {
    test('parses successfully when token_reference is absent', () {
      final json = {
        'id': 'pm-101',
        'provider': 'STRIPE',
        'card_brand': 'Mastercard',
        'last_four': '9999',
        'is_default': true,
      };

      final paymentMethod = PaymentMethod.fromMap(json);

      expect(paymentMethod.id, 'pm-101');
      expect(paymentMethod.provider, 'STRIPE');
      expect(paymentMethod.tokenReference, isNull);
      expect(paymentMethod.cardBrand, 'Mastercard');
      expect(paymentMethod.lastFour, '9999');
      expect(paymentMethod.isDefault, isTrue);
    });

    test('parses successfully when token_reference is null', () {
      final json = {
        'id': 'pm-102',
        'provider': 'PAYPAL',
        'token_reference': null,
        'card_brand': null,
        'last_four': null,
        'is_default': false,
      };

      final paymentMethod = PaymentMethod.fromMap(json);

      expect(paymentMethod.id, 'pm-102');
      expect(paymentMethod.provider, 'PAYPAL');
      expect(paymentMethod.tokenReference, isNull);
      expect(paymentMethod.cardBrand, isNull);
      expect(paymentMethod.lastFour, isNull);
      expect(paymentMethod.isDefault, isFalse);
    });

    test('parses successfully when token_reference is present', () {
      final json = {
        'id': 'pm-103',
        'provider': 'STRIPE',
        'token_reference': 'tok_visa_sample_123',
        'card_brand': 'VISA',
        'last_four': '1111',
        'is_default': true,
      };

      final paymentMethod = PaymentMethod.fromMap(json);

      expect(paymentMethod.id, 'pm-103');
      expect(paymentMethod.provider, 'STRIPE');
      expect(paymentMethod.tokenReference, 'tok_visa_sample_123');
      expect(paymentMethod.cardBrand, 'VISA');
      expect(paymentMethod.lastFour, '1111');
      expect(paymentMethod.isDefault, isTrue);
    });
  });
}
