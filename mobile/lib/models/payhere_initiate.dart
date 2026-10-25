import '../core/constants/payhere_config.dart';

/// PayHere Initiate Response Model
///
/// Encapsulates the PayHere checkout parameters returned by
/// POST /api/v1/payments/{transaction_id}/initiate.
///
/// The Flutter Mobile SDK uses [merchant_secret] and does not require web-checkout
/// parameters (`hash`, `return_url`, `cancel_url`).
class PayHereInitiateResponse {
  final String merchantId;
  final String orderId; // Transaction ID
  final String items; // Bill / item description
  final String currency;
  final String amount; // Exact string representation (e.g. "100.00")
  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  final String address;
  final String city;
  final String country;
  final String returnUrl;
  final String cancelUrl;
  final String notifyUrl;
  final String hash;

  const PayHereInitiateResponse({
    required this.merchantId,
    required this.orderId,
    required this.items,
    required this.currency,
    required this.amount,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.address,
    required this.city,
    required this.country,
    required this.returnUrl,
    required this.cancelUrl,
    required this.notifyUrl,
    required this.hash,
  });

  factory PayHereInitiateResponse.fromMap(Map<String, dynamic> map) {
    return PayHereInitiateResponse(
      merchantId: (map['merchant_id'] ?? map['merchantId'] ?? '').toString(),
      orderId: (map['order_id'] ?? map['orderId'] ?? '').toString(),
      items: (map['items'] ?? '').toString(),
      currency: (map['currency'] ?? 'LKR').toString(),
      amount: (map['amount'] ?? '0.00').toString(),
      firstName: (map['first_name'] ?? map['firstName'] ?? '').toString(),
      lastName: (map['last_name'] ?? map['lastName'] ?? '').toString(),
      email: (map['email'] ?? '').toString(),
      phone: (map['phone'] ?? '').toString(),
      address: (map['address'] ?? '').toString(),
      city: (map['city'] ?? '').toString(),
      country: (map['country'] ?? '').toString(),
      returnUrl: (map['return_url'] ?? map['returnUrl'] ?? '').toString(),
      cancelUrl: (map['cancel_url'] ?? map['cancelUrl'] ?? '').toString(),
      notifyUrl: (map['notify_url'] ?? map['notifyUrl'] ?? '').toString(),
      hash: (map['hash'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'merchant_id': merchantId,
      'order_id': orderId,
      'items': items,
      'currency': currency,
      'amount': amount,
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'phone': phone,
      'address': address,
      'city': city,
      'country': country,
      'return_url': returnUrl,
      'cancel_url': cancelUrl,
      'notify_url': notifyUrl,
      'hash': hash,
    };
  }

  /// Converts this response into the payment map expected by the PayHere Flutter SDK.
  /// Converts this response into the payment map expected by the PayHere Flutter SDK.
  ///
  /// The Flutter Mobile SDK requires [merchant_secret] (obtained by registering/whitelisting
  /// the app package in PayHere) and does not use web-hosted checkout parameters
  /// (`hash`, `return_url`, `cancel_url`).
  ///
  /// The secret is resolved from [merchantSecret] if provided, or falls back to
  /// [PayHereConfig.merchantSecret].
  Map<String, dynamic> toPaymentObject({
    bool sandbox = true,
    String? merchantSecret,
  }) {
    final effectiveSecret = (merchantSecret != null && merchantSecret.isNotEmpty)
        ? merchantSecret
        : PayHereConfig.merchantSecret;

    return <String, dynamic>{
      'sandbox': sandbox,
      'merchant_id': merchantId,
      'merchant_secret': effectiveSecret,
      'notify_url': notifyUrl,
      'order_id': orderId,
      'items': items,
      'amount': amount,
      'currency': currency,
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'phone': phone,
      'address': address,
      'city': city,
      'country': country,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PayHereInitiateResponse &&
        other.merchantId == merchantId &&
        other.orderId == orderId &&
        other.items == items &&
        other.currency == currency &&
        other.amount == amount &&
        other.firstName == firstName &&
        other.lastName == lastName &&
        other.email == email &&
        other.phone == phone &&
        other.address == address &&
        other.city == city &&
        other.country == country &&
        other.returnUrl == returnUrl &&
        other.cancelUrl == cancelUrl &&
        other.notifyUrl == notifyUrl &&
        other.hash == hash;
  }

  @override
  int get hashCode {
    return Object.hashAll([
      merchantId,
      orderId,
      items,
      currency,
      amount,
      firstName,
      lastName,
      email,
      phone,
      address,
      city,
      country,
      returnUrl,
      cancelUrl,
      notifyUrl,
      hash,
    ]);
  }

  @override
  String toString() {
    return 'PayHereInitiateResponse(merchantId: $merchantId, orderId: $orderId, amount: $amount $currency, items: $items)';
  }
}
