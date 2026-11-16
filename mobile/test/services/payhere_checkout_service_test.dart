import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/payhere_initiate.dart';
import 'package:mobile/services/payhere_checkout_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('payhere_mobilesdk_flutter');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('default checkout service sends no mobile secret to the SDK channel',
      () async {
    MethodCall? capturedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      capturedCall = call;
      return [
        {
          'success': true,
          'fldata': 'provider-payment-id',
        }
      ];
    });

    const response = PayHereInitiateResponse(
      merchantId: 'test-merchant',
      orderId: 'test-order',
      items: 'Test bill',
      currency: 'LKR',
      amount: '100.00',
      firstName: 'Test',
      lastName: 'User',
      email: 'test@example.com',
      phone: '+94770000000',
      address: 'Test address',
      city: 'Colombo',
      country: 'Sri Lanka',
      returnUrl: 'https://example.com/return',
      cancelUrl: 'https://example.com/cancel',
      notifyUrl: 'https://example.com/callback',
      hash: 'SERVER_GENERATED_HASH',
    );
    String? completedPaymentId;

    DefaultPayHereCheckoutService().startPayment(
      initiateResponse: response,
      onCompleted: (paymentId) {
        completedPaymentId = paymentId;
      },
      onError: fail,
      onDismissed: () => fail('Checkout was unexpectedly dismissed.'),
    );
    await pumpEventQueue();

    expect(capturedCall?.method, 'startPayment');
    final paymentMap = Map<String, dynamic>.from(
      capturedCall?.arguments as Map,
    );
    expect(paymentMap['merchant_id'], 'test-merchant');
    expect(paymentMap['order_id'], 'test-order');
    expect(paymentMap['amount'], '100.00');
    expect(paymentMap.containsKey('merchant_secret'), isFalse);
    expect(paymentMap.containsKey('hash'), isFalse);
    expect(paymentMap.containsKey('return_url'), isFalse);
    expect(paymentMap.containsKey('cancel_url'), isFalse);
    expect(completedPaymentId, 'provider-payment-id');
  });
}
