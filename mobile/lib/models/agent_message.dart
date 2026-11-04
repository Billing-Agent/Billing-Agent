import 'payment_plan.dart';

enum MessageSender { user, assistant }

enum PaymentPlanCardState {
  pending,    // Initial state: Confirm and Cancel buttons are active
  confirming, // User tapped confirm: buttons disabled, network request in flight
  confirmed,  // Successfully confirmed: PENDING transaction returned & checkout launched
  cancelled,  // User tapped cancel: card disabled without payment execution
  failed,     // Network or validation error occurred
}

class AgentMessage {
  final String id;
  final MessageSender sender;
  final String text;
  final DateTime timestamp;
  final PaymentPlan? paymentPlan;
  final String? confirmationId;
  final PaymentPlanCardState cardState;
  final String? errorMessage;

  const AgentMessage({
    required this.id,
    required this.sender,
    required this.text,
    required this.timestamp,
    this.paymentPlan,
    this.confirmationId,
    this.cardState = PaymentPlanCardState.pending,
    this.errorMessage,
  });

  bool get hasPaymentPlan =>
      paymentPlan != null && confirmationId != null && confirmationId!.isNotEmpty;

  AgentMessage copyWith({
    String? id,
    MessageSender? sender,
    String? text,
    DateTime? timestamp,
    PaymentPlan? paymentPlan,
    String? confirmationId,
    PaymentPlanCardState? cardState,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AgentMessage(
      id: id ?? this.id,
      sender: sender ?? this.sender,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      paymentPlan: paymentPlan ?? this.paymentPlan,
      confirmationId: confirmationId ?? this.confirmationId,
      cardState: cardState ?? this.cardState,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
