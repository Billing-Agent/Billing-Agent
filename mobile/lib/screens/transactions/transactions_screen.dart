import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(userTransactionsProvider);
        },
        child: transactionsAsync.when(
          data: (transactions) {
            if (transactions.isEmpty) {
              return const EmptyStateView(
                message: 'No transactions found.',
                icon: Icons.receipt_long_outlined,
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16.0),
              itemCount: transactions.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) => TransactionCard(
                transaction: transactions[index],
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ErrorStateView(
            error: error.toString(),
            onRetry: () => ref.invalidate(userTransactionsProvider),
          ),

        ),
      ),
    );
  }
}
