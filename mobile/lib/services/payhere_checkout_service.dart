import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:payhere_mobilesdk_flutter/payhere_mobilesdk_flutter.dart';
import '../models/payhere_initiate.dart';

/// Contract for launching the PayHere mobile checkout.
///
/// Abstracting the checkout behind this interface allows widget and integration
/// tests to verify checkout flows deterministically without requiring native
/// Android/iOS platform channel execution.
abstract class PayHereCheckoutService {
  void startPayment({
    required PayHereInitiateResponse initiateResponse,
    required void Function(String paymentId) onCompleted,
    required void Function(String error) onError,
    required void Function() onDismissed,
    bool isSandbox = true,
    String? merchantSecret,
  });
}

/// Default implementation that invokes PayHere Flutter SDK.
class DefaultPayHereCheckoutService implements PayHereCheckoutService {
  @override
  void startPayment({
    required PayHereInitiateResponse initiateResponse,
    required void Function(String paymentId) onCompleted,
    required void Function(String error) onError,
    required void Function() onDismissed,
    bool isSandbox = true,
    String? merchantSecret,
  }) {
    final paymentObject = initiateResponse.toPaymentObject(
      sandbox: isSandbox,
      merchantSecret: merchantSecret,
    );
    PayHere.startPayment(
      paymentObject,
      onCompleted,
      onError,
      onDismissed,
    );
  }
}

final payHereCheckoutServiceProvider = Provider<PayHereCheckoutService>((ref) {
  return DefaultPayHereCheckoutService();
});
