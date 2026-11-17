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
    final presentationStatus = _presentationStatus(isBusy);
    final showsConfirmationBoundary =
        cardState == PaymentPlanCardState.pending || isBusy;

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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusMedium),
                ),
                child: Icon(
                  Icons.verified_user_outlined,
                  size: 21,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: AppConstants.spacingMedium),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SECURE PAYMENT REVIEW',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: AppConstants.spacingXSmall),
                    Text(
                      _headerSubtitle(isBusy),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingLarge),
          Text(
            'Amount to pay',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppConstants.spacingXSmall),
          AmountText(
            key: const Key('payment_plan_amount'),
            amount: plan.amount,
            currency: plan.currency,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: AppConstants.spacingLarge),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppConstants.spacingMedium),
            decoration: BoxDecoration(
              color: semantic.surfaceSubtle,
              borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
              border: Border.all(color: semantic.border),
            ),
            child: Column(
              children: [
                _detailRow(
                  context,
                  label: 'Biller',
                  value: plan.biller,
                  valueKey: const Key('payment_plan_biller'),
                ),
                const SizedBox(height: AppConstants.spacingMedium),
                _detailRow(
                  context,
                  label: 'Account',
                  value: plan.maskedAccountNumber,
                  valueKey: const Key('payment_plan_account'),
                ),
                const SizedBox(height: AppConstants.spacingMedium),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        cardState == PaymentPlanCardState.pending && !isBusy
                            ? 'Bill status'
                            : 'Plan status',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    StatusChip(
                      key: const Key('payment_plan_status'),
                      status: presentationStatus,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (showsConfirmationBoundary) ...[
            const SizedBox(height: AppConstants.spacingMedium),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: AppConstants.iconSmall,
                  color: theme.colorScheme.secondary,
                ),
                const SizedBox(width: AppConstants.spacingSmall),
                Expanded(
                  child: Text(
                    'This plan cannot move money. You must confirm before checkout starts.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
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
                Expanded(
                  child: Text(
                    'Payment verified by the backend',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: semantic.onSuccessContainer,
                      fontWeight: FontWeight.w600,
                    ),
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
            if (errorMessage != null && errorMessage!.isNotEmpty) ...[
              const SizedBox(height: AppConstants.spacingSmall),
              Text(
                errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            const SizedBox(height: AppConstants.spacingLarge),
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

  String _presentationStatus(bool isBusy) {
    if (isBusy) return 'CONFIRMING';
    switch (cardState) {
      case PaymentPlanCardState.confirmed:
        return 'SUCCESS';
      case PaymentPlanCardState.cancelled:
        return 'CANCELLED';
      case PaymentPlanCardState.pending:
      case PaymentPlanCardState.confirming:
      case PaymentPlanCardState.failed:
        return cardState == PaymentPlanCardState.failed
            ? 'FAILED'
            : plan.billStatus;
    }
  }

  String _headerSubtitle(bool isBusy) {
    if (isBusy) return 'Confirming this plan with the backend';
    switch (cardState) {
      case PaymentPlanCardState.confirmed:
        return 'Final status was verified by the backend';
      case PaymentPlanCardState.cancelled:
        return 'This payment plan was cancelled';
      case PaymentPlanCardState.failed:
        return 'This payment plan could not be confirmed';
      case PaymentPlanCardState.pending:
      case PaymentPlanCardState.confirming:
        return 'Confirm the details before PayHere opens';
    }
  }

  Widget _detailRow(
    BuildContext context, {
    required String label,
    required String value,
    required Key valueKey,
  }) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: AppConstants.spacingMedium),
        Expanded(
          flex: 2,
          child: Text(
            value,
            key: valueKey,
            textAlign: TextAlign.end,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
