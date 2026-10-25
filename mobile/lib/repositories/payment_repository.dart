import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/payment_method.dart';
import '../models/transaction.dart';
import '../models/payhere_initiate.dart';
import '../services/api_client.dart';
import 'bill_repository.dart'; // To reuse apiClientProvider

final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return PaymentRepository(apiClient);
});

class PaymentRepository {
  final ApiClient _apiClient;

  PaymentRepository(this._apiClient);

  Future<List<PaymentMethod>> getUserPaymentMethods() async {
    final response = await _apiClient.get('/me/payment-methods');
    if (response is List) {
      return response.map((data) => PaymentMethod.fromMap(data)).toList();
    }
    return [];
  }

  Future<List<Transaction>> getUserTransactions() async {
    final response = await _apiClient.get('/me/transactions');
    if (response is List) {
      return response.map((data) => Transaction.fromMap(data)).toList();
    }
    return [];
  }

  Future<Transaction?> getPaymentStatus(String transactionId) async {
    final response = await _apiClient.get('/payments/$transactionId');
    if (response != null) {
      return Transaction.fromMap(response as Map<String, dynamic>);
    }
    return null;
  }
  
  Future<Transaction> preparePayment(String billId, String paymentMethodId, String idempotencyKey) async {
    final payload = {
      'bill_id': billId,
      'payment_method_id': paymentMethodId,
      'idempotency_key': idempotencyKey,
    };
    
    final response = await _apiClient.post('/payments/prepare', data: payload);
    return Transaction.fromMap(response as Map<String, dynamic>);
  }

  Future<PayHereInitiateResponse> initiatePayment(String transactionId) async {
    final response = await _apiClient.post('/payments/$transactionId/initiate');
    return PayHereInitiateResponse.fromMap(response as Map<String, dynamic>);
  }
}
