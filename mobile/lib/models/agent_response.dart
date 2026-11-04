import 'payment_plan.dart';

class AgentChatResponse {
  final String message;
  final String? intent;
  final bool requiresConfirmation;
  final PaymentPlan? paymentPlan;
  final String? confirmationId;
  final List<dynamic>? toolCalls;

  const AgentChatResponse({
    required this.message,
    this.intent,
    this.requiresConfirmation = false,
    this.paymentPlan,
    this.confirmationId,
    this.toolCalls,
  });

  factory AgentChatResponse.fromMap(Map<String, dynamic> map) {
    PaymentPlan? plan;
    if (map['payment_plan'] != null && map['payment_plan'] is Map<String, dynamic>) {
      plan = PaymentPlan.fromMap(map['payment_plan'] as Map<String, dynamic>);
    }

    return AgentChatResponse(
      message: (map['message'] ?? '').toString(),
      intent: map['intent'] as String?,
      requiresConfirmation: (map['requires_confirmation'] ?? map['requiresConfirmation'] ?? false) == true,
      paymentPlan: plan,
      confirmationId: (map['confirmation_id'] ?? map['confirmationId']) as String?,
      toolCalls: map['tool_calls'] as List<dynamic>?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'message': message,
      'intent': intent,
      'requires_confirmation': requiresConfirmation,
      'payment_plan': paymentPlan?.toMap(),
      'confirmation_id': confirmationId,
      'tool_calls': toolCalls,
    };
  }
}

class AgentPaymentConfirmResponse {
  final String transactionId;
  final String billId;
  final String amount;
  final String currency;
  final String status;

  const AgentPaymentConfirmResponse({
    required this.transactionId,
    required this.billId,
    required this.amount,
    required this.currency,
    required this.status,
  });

  factory AgentPaymentConfirmResponse.fromMap(Map<String, dynamic> map) {
    return AgentPaymentConfirmResponse(
      transactionId: (map['transaction_id'] ?? map['transactionId'] ?? '').toString(),
      billId: (map['bill_id'] ?? map['billId'] ?? '').toString(),
      amount: (map['amount'] ?? '').toString(),
      currency: (map['currency'] ?? 'LKR').toString(),
      status: (map['status'] ?? 'PENDING').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'transaction_id': transactionId,
      'bill_id': billId,
      'amount': amount,
      'currency': currency,
      'status': status,
    };
  }
}
