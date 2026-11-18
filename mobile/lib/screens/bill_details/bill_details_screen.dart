import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/bill.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/errors/app_errors.dart';
import '../../repositories/providers.dart';
import '../../widgets/amount_text.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/state_views.dart';
import '../../widgets/status_chip.dart';

class BillDetailsScreen extends ConsumerWidget {
  final Bill? initialBill;

  const BillDetailsScreen({super.key, this.initialBill});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (initialBill == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Bill Details')),
        body: const Center(child: Text('Bill not found.')),
      );
    }

    final billAsync = ref.watch(billDetailsProvider(initialBill!.id));

    return Scaffold(
      appBar: AppBar(title: const Text('Bill Details')),
      body: billAsync.when(
        data: (bill) {
          if (bill == null) {
            return const EmptyStateView(message: 'Bill not found.');
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.spacingLarge,
              AppConstants.spacingLarge,
              AppConstants.spacingLarge,
              AppConstants.spacingXXLarge,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppConstants.spacingXLarge),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                bill.biller,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            const SizedBox(
                              width: AppConstants.spacingMedium,
                            ),
                            StatusChip(status: bill.status),
                          ],
                        ),
                        const SizedBox(height: AppConstants.spacingXLarge),
                        Text(
                          'Amount due',
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                        const SizedBox(height: AppConstants.spacingXSmall),
                        AmountText(
                          key: const Key('bill_details_amount'),
                          amount: bill.amountDue,
                          currency: bill.currency,
                          style: Theme.of(context)
                              .textTheme
                              .headlineLarge
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppConstants.spacingLarge),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppConstants.spacingLarge),
                    child: Column(
                      children: [
                        _buildDetailRow(
                          context,
                          'Account',
                          _maskedAccount(bill.accountNumber),
                          valueKey: const Key('bill_details_masked_account'),
                        ),
                        const Divider(height: AppConstants.spacingXLarge),
                        _buildDetailRow(
                          context,
                          'Due Date',
                          bill.dueDate != null
                              ? '${bill.dueDate!.year}-${bill.dueDate!.month.toString().padLeft(2, '0')}-${bill.dueDate!.day.toString().padLeft(2, '0')}'
                              : 'Not available',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) {
          String msg = 'Failed to load bill details.';
          if (err is AppError) msg = err.message;
          return ErrorStateView(
            error: msg,
            onRetry: () => ref.invalidate(billDetailsProvider(initialBill!.id)),
          );
        },
      ),
      bottomNavigationBar: billAsync.maybeWhen(
        data: (bill) => bill != null && bill.status == 'UNPAID'
            ? _buildPaymentAction(context, bill)
            : null,
        orElse: () => null,
      ),
    );
  }

  Widget _buildPaymentAction(BuildContext context, Bill bill) {
    final semantic = AppSemanticColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: semantic.border)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.all(AppConstants.spacingLarge),
        child: PrimaryButton(
          key: const Key('bill_details_payment_button'),
          label: 'Continue to Payment',
          onPressed: () {
            context.push('/payment-confirmation', extra: bill);
          },
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    BuildContext context,
    String label,
    String value, {
    Key? valueKey,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        const SizedBox(width: AppConstants.spacingMedium),
        Expanded(
          child: Text(
            value,
            key: valueKey,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }

  String _maskedAccount(String accountNumber) {
    final trimmed = accountNumber.trim();
    if (trimmed.isEmpty || trimmed.length <= 4) return '••••';
    return '•••• ${trimmed.substring(trimmed.length - 4)}';
  }
}
