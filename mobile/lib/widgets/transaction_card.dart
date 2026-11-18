import 'package:flutter/material.dart';
import '../../models/transaction.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import 'amount_text.dart';
import 'status_chip.dart';

class TransactionCard extends StatelessWidget {
  final Transaction transaction;

  const TransactionCard({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    final isPending = transaction.status.trim().toUpperCase() == 'PENDING';
    final reference = transaction.providerReference?.trim().isNotEmpty == true
        ? transaction.providerReference!
        : transaction.id;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spacingLarge),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusMedium),
                  ),
                  child: Icon(
                    Icons.receipt_long_outlined,
                    color: theme.colorScheme.onPrimaryContainer,
                    size: 21,
                  ),
                ),
                const SizedBox(width: AppConstants.spacingMedium),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        transaction.biller,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppConstants.spacingXSmall),
                      Text(
                        _formatDate(transaction.createdAt),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppConstants.spacingSmall),
                StatusChip(status: transaction.status),
              ],
            ),
            const SizedBox(height: AppConstants.spacingLarge),
            Divider(color: semantic.border, height: 1),
            const SizedBox(height: AppConstants.spacingLarge),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reference',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppConstants.spacingXSmall),
                      Text(
                        reference,
                        key: const Key('transaction_reference'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppConstants.spacingMedium),
                Flexible(
                  child: AmountText(
                    amount: transaction.amount,
                    currency: transaction.currency,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            if (isPending) ...[
              const SizedBox(height: AppConstants.spacingMedium),
              Container(
                key: const Key('transaction_pending_explanation'),
                width: double.infinity,
                padding: const EdgeInsets.all(AppConstants.spacingMedium),
                decoration: BoxDecoration(
                  color: semantic.pendingContainer,
                  borderRadius:
                      BorderRadius.circular(AppConstants.radiusMedium),
                ),
                child: Text(
                  'Payment is awaiting final status confirmation.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: semantic.onPendingContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
