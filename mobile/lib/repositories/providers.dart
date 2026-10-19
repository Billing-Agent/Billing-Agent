import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/bill.dart';
import '../models/payment_method.dart';
import '../models/transaction.dart';
import 'bill_repository.dart';
import 'payment_repository.dart';

final userBillsProvider = FutureProvider<List<Bill>>((ref) async {
  final repository = ref.watch(billRepositoryProvider);
  return repository.getUserBills();
});

final billDetailsProvider = FutureProvider.family<Bill?, String>((ref, id) async {
  final repository = ref.watch(billRepositoryProvider);
  return repository.getBillById(id);
});

final userPaymentMethodsProvider = FutureProvider<List<PaymentMethod>>((ref) async {
  final repository = ref.watch(paymentRepositoryProvider);
  return repository.getUserPaymentMethods();
});

final userTransactionsProvider = FutureProvider<List<Transaction>>((ref) async {
  final repository = ref.watch(paymentRepositoryProvider);
  return repository.getUserTransactions();
});

final paymentStatusProvider = FutureProvider.family<Transaction?, String>((ref, transactionId) async {
  final repository = ref.watch(paymentRepositoryProvider);
  return repository.getPaymentStatus(transactionId);
});
