import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/bill_card.dart';
import '../../widgets/state_views.dart';
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
              const SizedBox(height: AppConstants.spacingXLarge),
              Text(
                'Quick actions',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: AppConstants.spacingMedium),
              _buildQuickActions(context),
              const SizedBox(height: AppConstants.spacingXLarge),
              _buildSectionHeader(context),
              const SizedBox(height: AppConstants.spacingMedium),
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
          'Welcome back, $name',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: AppConstants.paddingSmall),
        Text(
          'How can I help with your bills today?',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  Widget _buildAssistantBanner(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = AppSemanticColors.of(context);
    return InkWell(
      key: const Key('ask_billing_agent_card'),
      onTap: () => context.push('/assistant'),
      borderRadius: BorderRadius.circular(AppConstants.radiusLarge),
      child: Container(
        padding: const EdgeInsets.all(AppConstants.spacingXLarge),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.primaryContainer,
              theme.colorScheme.secondaryContainer.withOpacity(0.72),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppConstants.radiusLarge),
          border: Border.all(color: semantic.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius:
                        BorderRadius.circular(AppConstants.radiusMedium),
                  ),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    color: theme.colorScheme.onPrimary,
                    size: AppConstants.iconMedium,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.arrow_forward_rounded,
                  color: theme.colorScheme.primary,
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spacingLarge),
            Text(
              'Ask Billing Agent',
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppConstants.spacingXSmall),
            Text(
              'Review bills and prepare a payment using natural language. You stay in control of confirmation.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final payBill = OutlinedButton.icon(
          onPressed: () => context.go('/bills'),
          icon: const Icon(Icons.receipt_long_outlined),
          label: const Text('Pay a Bill'),
        );
        final history = OutlinedButton.icon(
          onPressed: () => context.go('/transactions'),
          icon: const Icon(Icons.history_rounded),
          label: const Text('View History'),
        );

        if (constraints.maxWidth < 340) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              payBill,
              const SizedBox(height: AppConstants.spacingSmall),
              history,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: payBill),
            const SizedBox(width: AppConstants.spacingMedium),
            Expanded(child: history),
          ],
        );
      },
    );
  }

  Widget _buildSectionHeader(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Upcoming bills',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                'Unpaid bills requiring attention',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        TextButton(
          key: const Key('home_view_all_bills'),
          onPressed: () => context.go('/bills'),
          child: const Text('View all'),
        ),
      ],
    );
  }

  Widget _buildUpcomingBills(
    AsyncValue billsAsync,
    BuildContext context,
    WidgetRef ref,
  ) {
    return billsAsync.when(
      data: (bills) {
        final unpaidBills = bills.where((b) => b.status == 'UNPAID').toList();
        if (unpaidBills.isEmpty) {
          return const EmptyStateView(
            message: 'You have no upcoming bills.',
            icon: Icons.check_circle_outline,
          );
        }
        return Column(
          children: unpaidBills
              .take(2)
              .map<Widget>((b) => BillCard(bill: b))
              .toList(),
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
