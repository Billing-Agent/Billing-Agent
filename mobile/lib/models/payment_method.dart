class PaymentMethod {
  final String id;
  final String provider;
  final String? tokenReference;
  final String? cardBrand;
  final String? lastFour;
  final bool isDefault;

  const PaymentMethod({
    required this.id,
    required this.provider,
    this.tokenReference,
    this.cardBrand,
    this.lastFour,
    required this.isDefault,
  });

  factory PaymentMethod.fromMap(Map<String, dynamic> map) {
    return PaymentMethod(
      id: map['id'] as String,
      provider: map['provider'] as String,
      tokenReference: map['token_reference'] as String?,
      cardBrand: map['card_brand'] as String?,
      lastFour: map['last_four'] as String?,
      isDefault: map['is_default'] as bool? ?? false,
    );
  }
}
