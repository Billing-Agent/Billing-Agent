import 'package:flutter/material.dart';
import '../../models/bill.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import 'package:go_router/go_router.dart';
import 'amount_text.dart';
import 'status_chip.dart';

class BillCard extends StatelessWidget {
  final Bill bill;

  const BillCard({super.key, required this.bill});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: AppConstants.paddingMedium),
      child: InkWell(
        onTap: () {
          context.push('/bills/${bill.id}', extra: bill);
        },
        borderRadius: BorderRadius.circular(AppConstants.radiusLarge),
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
                          bill.biller,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppConstants.spacingXSmall),
                        Text(
                          'Account ${_maskedAccount(bill.accountNumber)}',
                          key: const Key('bill_card_masked_account'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppConstants.spacingSmall),
                  StatusChip(status: bill.status),
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
                          'Due date',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: AppConstants.spacingXSmall),
                        Text(
                          bill.dueDate != null
                              ? '${bill.dueDate!.year}-${bill.dueDate!.month.toString().padLeft(2, '0')}-${bill.dueDate!.day.toString().padLeft(2, '0')}'
                              : 'Not available',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppConstants.spacingSmall),
                  Flexible(
                    child: AmountText(
                      amount: bill.amountDue,
                      currency: bill.currency,
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _maskedAccount(String accountNumber) {
    final trimmed = accountNumber.trim();
    if (trimmed.isEmpty || trimmed.length <= 4) return '••••';
    return '•••• ${trimmed.substring(trimmed.length - 4)}';
  }
}
