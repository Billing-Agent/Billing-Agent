import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import 'amount_text.dart';
import 'status_chip.dart';

class PaymentResultDialog extends StatelessWidget {
  final String status;
  final String title;
  final String transactionId;
  final String amount;
  final String currency;
  final String? message;
  final VoidCallback onPrimary;
  final VoidCallback? onRetry;

  const PaymentResultDialog({
    super.key,
    required this.status,
    required this.title,
    required this.transactionId,
    required this.amount,
    required this.currency,
    required this.onPrimary,
    this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final rawStatus = status.toUpperCase();
    final normalizedStatus = const {
      'SUCCESS',
      'PENDING',
      'FAILED',
      'CANCELLED',
    }.contains(rawStatus)
        ? rawStatus
        : 'UNKNOWN';
    final result = _presentationFor(
      normalizedStatus,
      theme,
      semantic,
      canRetry: onRetry != null,
    );

    return AlertDialog(
      key: const Key('payment_result_dialog'),
      icon: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: result.containerColor,
          shape: BoxShape.circle,
        ),
        child: Icon(result.icon, color: result.iconColor, size: 30),
      ),
      title: Text(
        title,
        key: const Key('payment_result_title'),
        textAlign: TextAlign.center,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusChip(status: normalizedStatus),
            if (message != null) ...[
              const SizedBox(height: AppConstants.spacingMedium),
              Text(
                message!,
                key: const Key('payment_result_message'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: AppConstants.spacingLarge),
            AmountText(
              key: const Key('payment_result_amount'),
              amount: amount,
              currency: currency,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppConstants.spacingMedium),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppConstants.spacingMedium),
              decoration: BoxDecoration(
                color: semantic.surfaceSubtle,
                borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
                border: Border.all(color: semantic.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Transaction reference',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppConstants.spacingXSmall),
                  SelectableText(
                    'Transaction ID: $transactionId',
                    key: const Key('payment_result_tx_id'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppConstants.spacingMedium),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: AppConstants.iconSmall,
                  color: theme.colorScheme.secondary,
                ),
                const SizedBox(width: AppConstants.spacingSmall),
                Expanded(
                  child: Text(
                    result.verificationCopy,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        if (onRetry != null)
          TextButton(
            key: const Key('payment_result_retry_button'),
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        FilledButton(
          key: const Key('payment_result_primary_button'),
          onPressed: onPrimary,
          child: Text(normalizedStatus == 'SUCCESS' ? 'View Bills' : 'OK'),
        ),
      ],
    );
  }

  _ResultPresentation _presentationFor(
    String status,
    ThemeData theme,
    AppSemanticColors semantic, {
    required bool canRetry,
  }) {
    switch (status) {
      case 'SUCCESS':
        return _ResultPresentation(
          icon: Icons.check_circle_outline_rounded,
          iconColor: semantic.success,
          containerColor: semantic.successContainer,
          verificationCopy:
              'Verified from PayHere provider status by the Billing Agent backend.',
        );
      case 'FAILED':
        return _ResultPresentation(
          icon: Icons.error_outline_rounded,
          iconColor: theme.colorScheme.error,
          containerColor: theme.colorScheme.errorContainer,
          verificationCopy: canRetry
              ? 'The backend did not confirm a successful payment. You can retry safely.'
              : 'The backend did not confirm a successful payment. Review your transaction history before trying again.',
        );
      case 'CANCELLED':
        return _ResultPresentation(
          icon: Icons.cancel_outlined,
          iconColor: semantic.neutral,
          containerColor: semantic.neutralContainer,
          verificationCopy:
              'No successful payment has been confirmed by the backend.',
        );
      case 'PENDING':
        return _ResultPresentation(
          icon: Icons.schedule_rounded,
          iconColor: semantic.pending,
          containerColor: semantic.pendingContainer,
          verificationCopy:
              'PayHere and the backend are still confirming the final payment status.',
        );
      default:
        return _ResultPresentation(
          icon: Icons.help_outline_rounded,
          iconColor: semantic.neutral,
          containerColor: semantic.neutralContainer,
          verificationCopy:
              'The payment status is unavailable. Review your transaction history for the latest backend status.',
        );
    }
  }
}

class _ResultPresentation {
  final IconData icon;
  final Color iconColor;
  final Color containerColor;
  final String verificationCopy;

  const _ResultPresentation({
    required this.icon,
    required this.iconColor,
    required this.containerColor,
    required this.verificationCopy,
  });
}
