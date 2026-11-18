import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_errors.dart';
import '../../widgets/state_views.dart';
import '../../widgets/transaction_card.dart';
import '../../repositories/providers.dart';

class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactionsAsync = ref.watch(userTransactionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction History'),
      ),
      body: transactionsAsync.when(
        data: (transactions) {
          if (transactions.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(userTransactionsProvider),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.62,
                    child: EmptyStateView(
                      message: 'No transactions found.',
                      icon: Icons.receipt_long_outlined,
                      actionLabel: 'Refresh',
                      onAction: () => ref.invalidate(userTransactionsProvider),
                    ),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(userTransactionsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(AppConstants.spacingLarge),
              itemCount: transactions.length + 1,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: AppConstants.spacingMedium),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(
                      bottom: AppConstants.spacingXSmall,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${transactions.length} ${transactions.length == 1 ? 'transaction' : 'transactions'}',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: AppConstants.spacingXSmall),
                        Text(
                          'Payment activity recorded for your account.',
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
                return TransactionCard(transaction: transactions[index - 1]);
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) {
          final message = error is AppError
              ? error.message
              : 'Failed to load transactions.';
          return ErrorStateView(
            error: message,
            onRetry: () => ref.invalidate(userTransactionsProvider),
          );
        },
      ),
    );
  }
}
