import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/bill.dart';
import '../models/payment_method.dart';
import '../models/transaction.dart';
import '../providers/auth_provider.dart';
import 'bill_repository.dart';
import 'payment_repository.dart';

final userBillsProvider = FutureProvider<List<Bill>>((ref) async {
  final session = ref.watch(authenticatedSessionProvider);
  if (session == null) return const [];
  final repository = ref.watch(billRepositoryProvider);
  final bills = await repository.getUserBills();
  return session.isActive ? bills : const [];
});

final billDetailsProvider =
    FutureProvider.family<Bill?, String>((ref, id) async {
  final session = ref.watch(authenticatedSessionProvider);
  if (session == null) return null;
  final repository = ref.watch(billRepositoryProvider);
  final bill = await repository.getBillById(id);
  return session.isActive ? bill : null;
});

final userPaymentMethodsProvider =
    FutureProvider<List<PaymentMethod>>((ref) async {
  final session = ref.watch(authenticatedSessionProvider);
  if (session == null) return const [];
  final repository = ref.watch(paymentRepositoryProvider);
  final methods = await repository.getUserPaymentMethods();
  return session.isActive ? methods : const [];
});

final userTransactionsProvider = FutureProvider<List<Transaction>>((ref) async {
  final session = ref.watch(authenticatedSessionProvider);
  if (session == null) return const [];
  final repository = ref.watch(paymentRepositoryProvider);
  final transactions = await repository.getUserTransactions();
  return session.isActive ? transactions : const [];
});

final paymentStatusProvider =
    FutureProvider.family<Transaction?, String>((ref, transactionId) async {
  final session = ref.watch(authenticatedSessionProvider);
  if (session == null) return null;
  final repository = ref.watch(paymentRepositoryProvider);
  final transaction = await repository.getPaymentStatus(transactionId);
  return session.isActive ? transaction : null;
});
