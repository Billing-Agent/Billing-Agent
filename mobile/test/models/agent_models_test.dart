import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/payment_plan.dart';
import 'package:mobile/models/agent_response.dart';
import 'package:mobile/models/agent_message.dart';

void main() {
  group('Agent Models Tests', () {
    test('PaymentPlan parses backend JSON correctly without double conversion', () {
      final map = {
        'bill_id': 'bill-uuid-12347',
        'biller': 'CEB',
        'account_number': '12347',
        'amount': '7200.00',
        'currency': 'LKR',
        'bill_status': 'UNPAID',
        'requires_confirmation': true,
      };

      final plan = PaymentPlan.fromMap(map);

      expect(plan.billId, 'bill-uuid-12347');
      expect(plan.biller, 'CEB');
      expect(plan.accountNumber, '12347');
      expect(plan.amount, '7200.00'); // Remains exact String
      expect(plan.currency, 'LKR');
      expect(plan.billStatus, 'UNPAID');
      expect(plan.requiresConfirmation, isTrue);
      expect(plan.maskedAccountNumber, '****2347');
    });

    test('PaymentPlan masks short account numbers cleanly', () {
      const plan = PaymentPlan(
        billId: 'b-1',
        biller: 'Water',
        accountNumber: '99',
        amount: '450.00',
        currency: 'LKR',
        billStatus: 'UNPAID',
      );
      expect(plan.maskedAccountNumber, '****99');
    });

    test('AgentChatResponse parses conversational response without plan', () {
      final map = {
        'message': 'Here are your registered bills.',
        'intent': 'VIEW_BILLS',
        'requires_confirmation': false,
        'payment_plan': null,
        'confirmation_id': null,
      };

      final response = AgentChatResponse.fromMap(map);

      expect(response.message, 'Here are your registered bills.');
      expect(response.intent, 'VIEW_BILLS');
      expect(response.requiresConfirmation, isFalse);
      expect(response.paymentPlan, isNull);
      expect(response.confirmationId, isNull);
    });

    test('AgentChatResponse parses structured payment plan and confirmation_id', () {
      final map = {
        'message': 'Would you like to pay your CEB bill?',
        'intent': 'PAY_BILL',
        'requires_confirmation': true,
        'payment_plan': {
          'bill_id': '1acb2cc9-b988-4106-88e9-4e84e077fc2e',
          'biller': 'CEB',
          'account_number': '12347',
          'amount': '7200.00',
          'currency': 'LKR',
          'bill_status': 'UNPAID',
          'requires_confirmation': true,
        },
        'confirmation_id': 'conf-token-abc-123',
      };

      final response = AgentChatResponse.fromMap(map);

      expect(response.requiresConfirmation, isTrue);
      expect(response.confirmationId, 'conf-token-abc-123');
      expect(response.paymentPlan, isNotNull);
      expect(response.paymentPlan!.biller, 'CEB');
      expect(response.paymentPlan!.amount, '7200.00');
    });

    test('AgentPaymentConfirmResponse parses backend confirmation response', () {
      final map = {
        'transaction_id': 'tx-66c9c31d',
        'bill_id': 'bill-1acb2cc9',
        'amount': '7200.00',
        'currency': 'LKR',
        'status': 'PENDING',
      };

      final confirm = AgentPaymentConfirmResponse.fromMap(map);

      expect(confirm.transactionId, 'tx-66c9c31d');
      expect(confirm.billId, 'bill-1acb2cc9');
      expect(confirm.amount, '7200.00');
      expect(confirm.currency, 'LKR');
      expect(confirm.status, 'PENDING');
    });

    test('AgentMessage helper properties and copyWith', () {
      final msg = AgentMessage(
        id: 'msg-1',
        sender: MessageSender.assistant,
        text: 'Hello',
        timestamp: DateTime.now(),
        cardState: PaymentPlanCardState.pending,
      );

      expect(msg.hasPaymentPlan, isFalse);

      final withPlan = msg.copyWith(
        confirmationId: 'token-123',
        paymentPlan: const PaymentPlan(
          billId: 'b-1',
          biller: 'CEB',
          accountNumber: '12347',
          amount: '7200.00',
          currency: 'LKR',
          billStatus: 'UNPAID',
        ),
      );

      expect(withPlan.hasPaymentPlan, isTrue);
      expect(withPlan.cardState, PaymentPlanCardState.pending);

      final cancelled = withPlan.copyWith(cardState: PaymentPlanCardState.cancelled);
      expect(cancelled.cardState, PaymentPlanCardState.cancelled);
    });
  });
}
