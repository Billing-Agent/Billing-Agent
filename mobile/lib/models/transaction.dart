class Transaction {
  final String id;
  final String biller;
  
  /// Amount represented as an exact string to avoid floating-point loss
  final String amount;
  
  final String currency;
  final String status; // 'PENDING', 'SUCCESS', 'FAILED', 'CANCELLED'
  final DateTime createdAt;
  final String? providerReference;

  const Transaction({
    required this.id,
    required this.biller,
    required this.amount,
    required this.currency,
    required this.status,
    required this.createdAt,
    this.providerReference,
  });

  factory Transaction.fromMap(Map<String, dynamic> map) {
    return Transaction(
      id: map['id'] as String,
      biller: map['biller'] as String? ?? 'Unknown',
      amount: map['amount'] as String,
      currency: map['currency'] as String,
      status: map['status'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      providerReference: map['provider_reference'] as String?,
    );
  }
}
