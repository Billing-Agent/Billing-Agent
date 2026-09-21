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
            return const EmptyStateView(message: 'You have no bills.');
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(userBillsProvider);
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(AppConstants.paddingMedium),
              itemCount: bills.length,
              itemBuilder: (context, index) {
                return BillCard(bill: bills[index]);
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
