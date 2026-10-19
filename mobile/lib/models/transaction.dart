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
    DateTime parseDate(dynamic dateVal) {
      if (dateVal is String) {
        return DateTime.tryParse(dateVal) ?? DateTime.now();
      }
      return DateTime.now();
    }

    return Transaction(
      id: (map['id'] ?? map['transaction_id'] ?? '').toString(),
      biller: map['biller'] as String? ?? 'Unknown',
      amount: map['amount']?.toString() ?? '0.00',
      currency: map['currency'] as String? ?? 'LKR',
      status: map['status'] as String? ?? 'PENDING',
      createdAt: parseDate(map['created_at']),
      providerReference: (map['provider_reference'] ?? map['providerReference']) as String?,
    );
  }
}
