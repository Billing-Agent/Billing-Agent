import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../screens/home/home_screen.dart';
import '../../screens/bills/bills_screen.dart';
import '../../screens/transactions/transactions_screen.dart';
import '../../screens/settings/settings_screen.dart';
import '../../screens/bill_details/bill_details_screen.dart';
import '../../screens/payment/payment_confirmation_screen.dart';
import '../../widgets/scaffold_with_nav_bar.dart';
import '../../models/bill.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

final GoRouter appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return ScaffoldWithNavBar(navigationShell: navigationShell);
      },
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const HomeScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/bills',
              builder: (context, state) => const BillsScreen(),
              routes: [
                GoRoute(
                  path: ':id',
                  parentNavigatorKey: _rootNavigatorKey,
                  builder: (context, state) {
                    final bill = state.extra as Bill?;
                    return BillDetailsScreen(initialBill: bill);
                  },
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/transactions',
              builder: (context, state) => const TransactionsScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsScreen(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/payment-confirmation',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        final bill = state.extra as Bill?;
        return PaymentConfirmationScreen(bill: bill);
      },
    ),
  ],
);
