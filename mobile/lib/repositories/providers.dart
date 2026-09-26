import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/bill.dart';
import '../models/payment_method.dart';
import '../providers/auth_provider.dart';
import 'bill_repository.dart';
import 'payment_repository.dart';

final userBillsProvider = FutureProvider<List<Bill>>((ref) async {
  final authState = ref.watch(authProvider);
  final userId = authState.user?.id;
  final repository = ref.watch(billRepositoryProvider);
  return repository.getUserBills(userId);
});

final billDetailsProvider = FutureProvider.family<Bill?, String>((ref, id) async {
  final repository = ref.watch(billRepositoryProvider);
  return repository.getBillById(id);
});

final userPaymentMethodsProvider = FutureProvider<List<PaymentMethod>>((ref) async {
  final authState = ref.watch(authProvider);
  final userId = authState.user?.id;
  final repository = ref.watch(paymentRepositoryProvider);
  return repository.getUserPaymentMethods(userId);
});
