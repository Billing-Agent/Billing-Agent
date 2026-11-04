import 'package:flutter/material.dart';
import '../models/agent_message.dart';
import '../models/payment_plan.dart';
import '../core/utils/money_utils.dart';

class PaymentPlanCard extends StatelessWidget {
  final PaymentPlan plan;
  final PaymentPlanCardState cardState;
  final bool isConfirming;
  final String? errorMessage;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const PaymentPlanCard({
    super.key,
    required this.plan,
    required this.cardState,
    required this.isConfirming,
    this.errorMessage,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPending = cardState == PaymentPlanCardState.pending && !isConfirming;
    final isBusy = cardState == PaymentPlanCardState.confirming || (isConfirming && cardState == PaymentPlanCardState.pending);

    return Container(
      key: const Key('payment_plan_card'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cardState == PaymentPlanCardState.confirmed
              ? Colors.green.shade300
              : cardState == PaymentPlanCardState.cancelled
                  ? Colors.grey.shade300
                  : theme.primaryColor.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Biller + Status Chip
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                plan.biller,
                key: const Key('payment_plan_biller'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: plan.billStatus.toUpperCase() == 'UNPAID'
                      ? Colors.orange.shade50
                      : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: plan.billStatus.toUpperCase() == 'UNPAID'
                        ? Colors.orange.shade300
                        : Colors.green.shade300,
                  ),
                ),
                child: Text(
                  plan.billStatus.toUpperCase(),
                  key: const Key('payment_plan_status'),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: plan.billStatus.toUpperCase() == 'UNPAID'
                        ? Colors.orange.shade800
                        : Colors.green.shade800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Masked Account Number
          Text(
            'Account ${plan.maskedAccountNumber}',
            key: const Key('payment_plan_account'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 12),

          // Formatted Amount
          Text(
            MoneyUtils.formatAmount(plan.amount, currency: plan.currency),
            key: const Key('payment_plan_amount'),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.primaryColor,
            ),
          ),
          const SizedBox(height: 8),

          // State indicators or Action Buttons
          if (cardState == PaymentPlanCardState.confirmed) ...[
            const Divider(height: 24),
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Payment confirmed and launched',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.green.shade800,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ] else if (cardState == PaymentPlanCardState.cancelled) ...[
            const Divider(height: 24),
            Row(
              children: [
                Icon(Icons.cancel_outlined, color: Colors.grey.shade600, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Payment cancelled',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade700,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ] else ...[
            Text(
              'Would you like to proceed with this payment?',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade700,
              ),
            ),
            if (errorMessage != null && errorMessage!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    key: const Key('payment_plan_confirm_button'),
                    onPressed: isPending ? onConfirm : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primaryColor,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: theme.primaryColor.withOpacity(0.5),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: isBusy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Confirm Payment',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    key: const Key('payment_plan_cancel_button'),
                    onPressed: isPending ? onCancel : null,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
