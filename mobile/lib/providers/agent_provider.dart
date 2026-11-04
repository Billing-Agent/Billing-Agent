import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/agent_message.dart';
import '../models/transaction.dart';
import '../services/agent_service.dart';
import '../services/payhere_checkout_service.dart';
import '../repositories/payment_repository.dart';
import '../repositories/providers.dart';
import '../core/errors/app_errors.dart';

class AgentChatState {
  final List<AgentMessage> messages;
  final bool isLoading;
  final bool isConfirming;
  final String? activeConfirmationId;
  final String? errorMessage;

  const AgentChatState({
    this.messages = const [],
    this.isLoading = false,
    this.isConfirming = false,
    this.activeConfirmationId,
    this.errorMessage,
  });

  AgentChatState copyWith({
    List<AgentMessage>? messages,
    bool? isLoading,
    bool? isConfirming,
    String? activeConfirmationId,
    bool clearActiveConfirmationId = false,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AgentChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isConfirming: isConfirming ?? this.isConfirming,
      activeConfirmationId: clearActiveConfirmationId
          ? null
          : (activeConfirmationId ?? this.activeConfirmationId),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class AgentChatNotifier extends StateNotifier<AgentChatState> {
  final Ref _ref;
  final Uuid _uuid;

  AgentChatNotifier(this._ref, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid(),
        super(const AgentChatState());

  AgentService get _agentService => _ref.read(agentServiceProvider);
  PaymentRepository get _paymentRepository => _ref.read(paymentRepositoryProvider);
  PayHereCheckoutService get _checkoutService => _ref.read(payHereCheckoutServiceProvider);

  /// Send a natural language message to the Billing Assistant.
  ///
  /// CRITICAL SECURITY:
  /// Even if the user message is "yes", "confirm", or "proceed", it is sent
  /// strictly as a chat message. It does NOT invoke confirmation or trigger PayHere.
  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.isLoading || state.isConfirming) {
      return;
    }

    final userMessage = AgentMessage(
      id: _uuid.v4(),
      sender: MessageSender.user,
      text: trimmed,
      timestamp: DateTime.now(),
    );

    state = state.copyWith(
      messages: [...state.messages, userMessage],
      isLoading: true,
      clearError: true,
    );

    try {
      final response = await _agentService.sendMessage(trimmed);

      final assistantMessage = AgentMessage(
        id: _uuid.v4(),
        sender: MessageSender.assistant,
        text: response.message,
        timestamp: DateTime.now(),
        paymentPlan: response.paymentPlan,
        confirmationId: response.confirmationId,
        cardState: PaymentPlanCardState.pending,
      );

      state = state.copyWith(
        messages: [...state.messages, assistantMessage],
        isLoading: false,
      );
    } catch (e) {
      String userErrorMsg = "Unable to reach the billing assistant. Please try again.";
      if (e is AppError) {
        userErrorMsg = e.message;
      }

      final errorAssistantMessage = AgentMessage(
        id: _uuid.v4(),
        sender: MessageSender.assistant,
        text: userErrorMsg,
        timestamp: DateTime.now(),
      );

      state = state.copyWith(
        messages: [...state.messages, errorAssistantMessage],
        isLoading: false,
        errorMessage: userErrorMsg,
      );
    }
  }

  /// Cancel a payment plan proposed in a card.
  ///
  /// CRITICAL:
  /// Cancelling does NOT call the confirmation endpoint, does NOT launch PayHere,
  /// and does NOT create a transaction.
  void cancelPlan(String messageId) {
    state = state.copyWith(
      messages: state.messages.map((m) {
        if (m.id == messageId) {
          return m.copyWith(cardState: PaymentPlanCardState.cancelled);
        }
        return m;
      }).toList(),
    );
  }

  /// Confirm payment via explicit user action on the card button.
  ///
  /// Flow:
  /// 1. Immediately locks out double-taps.
  /// 2. Calls POST /api/v1/agent/payments/confirm with ONLY { "confirmation_id": confirmationId }.
  /// 3. Validates returned transaction_id and PENDING status.
  /// 4. Reuses existing PayHere checkout flow:
  ///    - calls /payments/{transaction_id}/initiate
  ///    - launches PayHere SDK
  ///    - polls backend status
  ///    - on SUCCESS: invalidates bills and transactions providers, shows success
  /// 5. Backend remains authoritative financial truth.
  Future<void> confirmPaymentPlan({
    required String messageId,
    required String confirmationId,
    void Function(String error)? onError,
    void Function({
      required String status,
      required String title,
      required String transactionId,
      required String amount,
      required String currency,
      String? message,
    })? onPaymentResult,
  }) async {
    // 1. Prevent duplicate confirmation requests or double taps
    if (state.isConfirming || state.activeConfirmationId != null) {
      return;
    }

    final targetMessage = state.messages.firstWhere(
      (m) => m.id == messageId,
      orElse: () => AgentMessage(
        id: '',
        sender: MessageSender.assistant,
        text: '',
        timestamp: DateTime.now(),
      ),
    );

    if (targetMessage.id.isEmpty || targetMessage.cardState != PaymentPlanCardState.pending) {
      return;
    }

    state = state.copyWith(
      isConfirming: true,
      activeConfirmationId: confirmationId,
      messages: state.messages.map((m) {
        if (m.id == messageId) {
          return m.copyWith(cardState: PaymentPlanCardState.confirming);
        }
        return m;
      }).toList(),
      clearError: true,
    );

    try {
      // 2. Call backend confirmation endpoint with ONLY confirmation_id
      final confirmResponse = await _agentService.confirmPayment(confirmationId);

      final transactionId = confirmResponse.transactionId;
      if (transactionId.isEmpty) {
        throw ServerError("Invalid transaction reference received from server.");
      }

      // 3. Initiate PayHere parameters using existing flow
      final initiateResponse = await _paymentRepository.initiatePayment(transactionId);

      // 4. Launch PayHere mobile checkout
      _checkoutService.startPayment(
        initiateResponse: initiateResponse,
        onCompleted: (paymentId) {
          _verifyBackendStatus(
            transactionId: transactionId,
            messageId: messageId,
            wasDismissed: false,
            onPaymentResult: onPaymentResult,
            onError: onError,
          );
        },
        onError: (err) {
          _verifyBackendStatus(
            transactionId: transactionId,
            messageId: messageId,
            wasDismissed: false,
            fallbackErrorMessage: err.isNotEmpty ? err : "Payment was interrupted.",
            onPaymentResult: onPaymentResult,
            onError: onError,
          );
        },
        onDismissed: () {
          _verifyBackendStatus(
            transactionId: transactionId,
            messageId: messageId,
            wasDismissed: true,
            onPaymentResult: onPaymentResult,
            onError: onError,
          );
        },
      );
    } catch (e) {
      String userErrorMsg = "Unable to confirm payment. Please try again.";
      if (e is AppError) {
        userErrorMsg = e.message;
      }

      state = state.copyWith(
        isConfirming: false,
        clearActiveConfirmationId: true,
        errorMessage: userErrorMsg,
        messages: state.messages.map((m) {
          if (m.id == messageId) {
            return m.copyWith(
              cardState: PaymentPlanCardState.failed,
              errorMessage: userErrorMsg,
            );
          }
          return m;
        }).toList(),
      );

      onError?.call(userErrorMsg);
    }
  }

  /// Polls backend transaction status up to 3 times to verify financial truth.
  Future<void> _verifyBackendStatus({
    required String transactionId,
    required String messageId,
    required bool wasDismissed,
    String? fallbackErrorMessage,
    void Function(String error)? onError,
    void Function({
      required String status,
      required String title,
      required String transactionId,
      required String amount,
      required String currency,
      String? message,
    })? onPaymentResult,
  }) async {
    try {
      Transaction? transaction;
      int attempts = 0;
      const maxAttempts = 3;

      while (attempts < maxAttempts) {
        transaction = await _paymentRepository.getPaymentStatus(transactionId);
        if (transaction != null && transaction.status != 'PENDING') {
          break;
        }
        attempts++;
        if (attempts < maxAttempts && !wasDismissed) {
          await Future.delayed(const Duration(milliseconds: 1200));
        } else {
          break;
        }
      }

      state = state.copyWith(
        isConfirming: false,
        clearActiveConfirmationId: true,
      );

      if (transaction == null) {
        final err = fallbackErrorMessage ?? "Unable to verify payment status.";
        onError?.call(err);
        return;
      }

      final status = transaction.status.toUpperCase();

      if (status == 'SUCCESS') {
        // Authoritative backend SUCCESS: Invalidate cached bills & transactions
        _ref.invalidate(userBillsProvider);
        _ref.invalidate(userTransactionsProvider);

        state = state.copyWith(
          messages: state.messages.map((m) {
            if (m.id == messageId) {
              return m.copyWith(cardState: PaymentPlanCardState.confirmed);
            }
            return m;
          }).toList(),
        );

        onPaymentResult?.call(
          status: 'SUCCESS',
          title: 'Payment Successful',
          transactionId: transaction.id,
          amount: transaction.amount,
          currency: transaction.currency,
        );
      } else if (status == 'FAILED') {
        state = state.copyWith(
          messages: state.messages.map((m) {
            if (m.id == messageId) {
              return m.copyWith(cardState: PaymentPlanCardState.failed);
            }
            return m;
          }).toList(),
        );

        onPaymentResult?.call(
          status: 'FAILED',
          title: 'Payment Failed',
          transactionId: transaction.id,
          amount: transaction.amount,
          currency: transaction.currency,
        );
      } else if (status == 'CANCELLED') {
        state = state.copyWith(
          messages: state.messages.map((m) {
            if (m.id == messageId) {
              return m.copyWith(cardState: PaymentPlanCardState.cancelled);
            }
            return m;
          }).toList(),
        );

        onPaymentResult?.call(
          status: 'CANCELLED',
          title: 'Payment Cancelled',
          transactionId: transaction.id,
          amount: transaction.amount,
          currency: transaction.currency,
        );
      } else {
        // Status remains PENDING on backend
        if (wasDismissed) {
          onPaymentResult?.call(
            status: 'CANCELLED',
            title: 'Payment Cancelled',
            transactionId: transaction.id,
            amount: transaction.amount,
            currency: transaction.currency,
          );
        } else {
          onPaymentResult?.call(
            status: 'PENDING',
            title: 'Payment Processing',
            message: 'Your payment is still being confirmed by the provider.',
            transactionId: transaction.id,
            amount: transaction.amount,
            currency: transaction.currency,
          );
        }
      }
    } catch (e) {
      state = state.copyWith(
        isConfirming: false,
        clearActiveConfirmationId: true,
      );
      String userErrorMsg = "Unable to verify payment status with server.";
      if (e is AppError) {
        userErrorMsg = e.message;
      }
      onError?.call(userErrorMsg);
    }
  }
}

final agentChatProvider = StateNotifierProvider<AgentChatNotifier, AgentChatState>((ref) {
  return AgentChatNotifier(ref);
});
