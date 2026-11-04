import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../widgets/bill_card.dart';
import '../../widgets/state_views.dart';
import '../../widgets/primary_button.dart';
import '../../core/errors/app_errors.dart';
import '../../repositories/providers.dart';

import '../../providers/auth_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final billsAsync = ref.watch(userBillsProvider);
    final authState = ref.watch(authProvider);
    final userName = authState.user?.name ?? "User";

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(userBillsProvider);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppConstants.paddingMedium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildGreeting(context, userName),
              const SizedBox(height: AppConstants.paddingMedium),
              _buildAssistantBanner(context),
              const SizedBox(height: AppConstants.paddingLarge),
              _buildQuickActions(context),
              const SizedBox(height: AppConstants.paddingLarge),
              Text(
                'Upcoming Bills',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppConstants.paddingMedium),
              _buildUpcomingBills(billsAsync, context, ref),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGreeting(BuildContext context, String name) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Good morning, $name',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: AppConstants.paddingSmall),
        Text(
          'How can I help with your bills today?',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildAssistantBanner(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      key: const Key('ask_billing_agent_card'),
      onTap: () => context.push('/assistant'),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              theme.primaryColor.withOpacity(0.08),
              theme.primaryColor.withOpacity(0.02),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.primaryColor.withOpacity(0.2),
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: theme.primaryColor,
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ask Billing Agent',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Pay bills or check balances using natural language',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: theme.primaryColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: PrimaryButton(
            label: 'Pay a Bill',
            onPressed: () => context.go('/bills'),
          ),
        ),
        const SizedBox(width: AppConstants.paddingMedium),
        Expanded(
          child: OutlinedButton(
            onPressed: () => context.go('/transactions'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('View History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _buildUpcomingBills(AsyncValue billsAsync, BuildContext context, WidgetRef ref) {
    return billsAsync.when(
      data: (bills) {
        final unpaidBills = bills.where((b) => b.status == 'UNPAID').toList();
        if (unpaidBills.isEmpty) {
          return const EmptyStateView(message: 'You have no upcoming bills.', icon: Icons.check_circle_outline);
        }
        return Column(
          children: unpaidBills.take(2).map<Widget>((b) => BillCard(bill: b)).toList(),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) {
        String msg = "Failed to load bills.";
        if (err is AppError) {
          msg = err.message;
        }
        return ErrorStateView(
          error: msg,
          onRetry: () => ref.invalidate(userBillsProvider),
        );
      },
    );
  }
}
