import 'package:flutter/material.dart';
import '../models/agent_message.dart';
import '../models/payment_plan.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import 'amount_text.dart';
import 'status_chip.dart';

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
    final semantic = AppSemanticColors.of(context);
    final isPending =
        cardState == PaymentPlanCardState.pending && !isConfirming;
    final isBusy = cardState == PaymentPlanCardState.confirming ||
        (isConfirming && cardState == PaymentPlanCardState.pending);

    return Container(
      key: const Key('payment_plan_card'),
      margin: const EdgeInsets.symmetric(vertical: AppConstants.spacingSmall),
      padding: const EdgeInsets.all(AppConstants.spacingLarge),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusLarge),
        border: Border.all(
          color: cardState == PaymentPlanCardState.confirmed
              ? semantic.success
              : cardState == PaymentPlanCardState.cancelled
                  ? semantic.neutral
                  : semantic.border,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow,
            blurRadius: 8,
            offset: const Offset(0, 2),
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
              Expanded(
                child: Text(
                  plan.biller,
                  key: const Key('payment_plan_biller'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: AppConstants.spacingSmall),
              StatusChip(
                key: const Key('payment_plan_status'),
                status: plan.billStatus,
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Masked Account Number
          Text(
            'Account ${plan.maskedAccountNumber}',
            key: const Key('payment_plan_account'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),

          // Formatted Amount
          AmountText(
            key: const Key('payment_plan_amount'),
            amount: plan.amount,
            currency: plan.currency,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),

          // State indicators or Action Buttons
          if (cardState == PaymentPlanCardState.confirmed) ...[
            const Divider(height: 24),
            Row(
              children: [
                Icon(
                  Icons.check_circle,
                  color: semantic.success,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Payment confirmed and launched',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: semantic.onSuccessContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ] else if (cardState == PaymentPlanCardState.cancelled) ...[
            const Divider(height: 24),
            Row(
              children: [
                Icon(
                  Icons.cancel_outlined,
                  color: semantic.neutral,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Payment cancelled',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: semantic.onNeutralContainer,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ] else ...[
            Text(
              'Would you like to proceed with this payment?',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (errorMessage != null && errorMessage!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                key: const Key('payment_plan_confirm_button'),
                onPressed: isPending ? onConfirm : null,
                child: isBusy
                    ? SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: isPending
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.primary,
                        ),
                      )
                    : const Text('Confirm Payment'),
              ),
            ),
            const SizedBox(height: AppConstants.spacingSmall),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: const Key('payment_plan_cancel_button'),
                onPressed: isPending ? onCancel : null,
                child: const Text('Cancel'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
