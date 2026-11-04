class PaymentPlan {
  final String billId;
  final String biller;
  final String accountNumber;
  final String amount;
  final String currency;
  final String billStatus;
  final bool requiresConfirmation;

  const PaymentPlan({
    required this.billId,
    required this.biller,
    required this.accountNumber,
    required this.amount,
    required this.currency,
    required this.billStatus,
    this.requiresConfirmation = true,
  });

  /// Displays masked account number (e.g., '****2347' for '12347').
  String get maskedAccountNumber {
    if (accountNumber.length <= 4) {
      return '****$accountNumber';
    }
    final suffix = accountNumber.substring(accountNumber.length - 4);
    return '****$suffix';
  }

  factory PaymentPlan.fromMap(Map<String, dynamic> map) {
    return PaymentPlan(
      billId: (map['bill_id'] ?? map['billId'] ?? '').toString(),
      biller: (map['biller'] ?? '').toString(),
      accountNumber: (map['account_number'] ?? map['accountNumber'] ?? '').toString(),
      amount: (map['amount'] ?? '').toString(),
      currency: (map['currency'] ?? 'LKR').toString(),
      billStatus: (map['bill_status'] ?? map['billStatus'] ?? '').toString(),
      requiresConfirmation: (map['requires_confirmation'] ?? map['requiresConfirmation'] ?? true) == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'bill_id': billId,
      'biller': biller,
      'account_number': accountNumber,
      'amount': amount,
      'currency': currency,
      'bill_status': billStatus,
      'requires_confirmation': requiresConfirmation,
    };
  }
}
