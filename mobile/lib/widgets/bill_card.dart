import 'package:flutter/material.dart';
import '../../models/bill.dart';
import '../../core/constants/app_constants.dart';
import 'package:go_router/go_router.dart';
import 'amount_text.dart';
import 'status_chip.dart';

class BillCard extends StatelessWidget {
  final Bill bill;

  const BillCard({super.key, required this.bill});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppConstants.paddingMedium),
      child: InkWell(
        onTap: () {
          context.push('/bills/${bill.id}', extra: bill);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.paddingMedium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      bill.biller,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  const SizedBox(width: AppConstants.spacingSmall),
                  StatusChip(status: bill.status),
                ],
              ),
              const SizedBox(height: AppConstants.paddingSmall),
              Text(
                'Acc: ****${bill.accountNumber.length > 4 ? bill.accountNumber.substring(bill.accountNumber.length - 4) : bill.accountNumber}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppConstants.paddingMedium),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Due Date',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          bill.dueDate != null
                              ? '${bill.dueDate!.year}-${bill.dueDate!.month.toString().padLeft(2, '0')}-${bill.dueDate!.day.toString().padLeft(2, '0')}'
                              : 'Not available',
                          style: Theme.of(context).textTheme.bodyMedium,
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
                            color: Theme.of(context).colorScheme.primary,
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
}
