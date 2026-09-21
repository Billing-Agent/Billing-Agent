import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/bill.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/money_utils.dart';
import '../../core/errors/app_errors.dart';
import '../../repositories/providers.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/state_views.dart';

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
            padding: const EdgeInsets.all(AppConstants.paddingMedium),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppConstants.paddingLarge),
                    child: Column(
                      children: [
                        _buildDetailRow(context, 'Biller', bill.biller),
                        const Divider(height: AppConstants.paddingLarge),
                        _buildDetailRow(context, 'Account Number', bill.accountNumber),
                        const Divider(height: AppConstants.paddingLarge),
                        _buildDetailRow(context, 'Due Date', '${bill.dueDate.year}-${bill.dueDate.month.toString().padLeft(2, '0')}-${bill.dueDate.day.toString().padLeft(2, '0')}'),
                        const Divider(height: AppConstants.paddingLarge),
                        _buildDetailRow(context, 'Status', bill.status),
                        const Divider(height: AppConstants.paddingLarge),
                        _buildDetailRow(
                          context, 
                          'Amount Due', 
                          MoneyUtils.formatAmount(bill.amountDue, currency: bill.currency),
                          isTotal: true,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppConstants.paddingLarge * 2),
                if (bill.status == 'UNPAID')
                  PrimaryButton(
                    label: 'Continue to Payment',
                    onPressed: () {
                      context.push('/payment-confirmation', extra: bill);
                    },
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
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value, {bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Colors.grey[600],
            fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
            fontSize: isTotal ? 20 : null,
            color: isTotal ? Theme.of(context).colorScheme.primary : null,
          ),
        ),
      ],
    );
  }
}
