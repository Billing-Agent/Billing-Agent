class Bill {
  final String id;
  final String biller;
  final String accountNumber;
  
  /// Amount represented as an exact string to avoid floating-point loss
  final String amountDue;
  
  final String currency;
  final String status; // e.g., 'UNPAID', 'PAID'
  final DateTime? dueDate;

  const Bill({
    required this.id,
    required this.biller,
    required this.accountNumber,
    required this.amountDue,
    required this.currency,
    required this.status,
    required this.dueDate,
  });

  factory Bill.fromMap(Map<String, dynamic> map) {
    return Bill(
      id: map['id'] as String,
      biller: map['biller'] as String,
      accountNumber: map['account_number'] as String,
      amountDue: map['amount_due'] as String,
      currency: map['currency'] as String,
      status: map['status'] as String,
      dueDate: map['due_date'] != null
          ? DateTime.parse(map['due_date'] as String)
          : null,
    );
  }
}
