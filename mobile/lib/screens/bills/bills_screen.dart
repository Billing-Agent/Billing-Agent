import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_errors.dart';
import '../../repositories/providers.dart';
import '../../widgets/bill_card.dart';
import '../../widgets/state_views.dart';

class BillsScreen extends ConsumerWidget {
  const BillsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final billsAsync = ref.watch(userBillsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Bills'),
      ),
      body: billsAsync.when(
        data: (bills) {
          if (bills.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(userBillsProvider),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.62,
                    child: EmptyStateView(
                      message: 'You have no bills.',
                      actionLabel: 'Refresh',
                      onAction: () => ref.invalidate(userBillsProvider),
                    ),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(userBillsProvider);
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(AppConstants.paddingMedium),
              itemCount: bills.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(
                      bottom: AppConstants.spacingLarge,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${bills.length} ${bills.length == 1 ? 'bill' : 'bills'}',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: AppConstants.spacingXSmall),
                        Text(
                          'Review amounts, due dates and payment status.',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  );
                }
                return BillCard(bill: bills[index - 1]);
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) {
          String msg = 'Failed to load bills.';
          if (err is AppError) {
            msg = err.message;
          }
          return ErrorStateView(
            error: msg,
            onRetry: () => ref.invalidate(userBillsProvider),
          );
        },
      ),
    );
  }
}
