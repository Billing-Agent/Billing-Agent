import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/payment_method.dart';
import '../models/transaction.dart';
import '../services/api_client.dart';
import '../core/constants/api_config.dart';
import 'bill_repository.dart'; // To reuse apiClientProvider

final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return PaymentRepository(apiClient);
});

class PaymentRepository {
  final ApiClient _apiClient;

  PaymentRepository(this._apiClient);

  Future<List<PaymentMethod>> getUserPaymentMethods() async {
    final response = await _apiClient.get('/users/${ApiConfig.devUserId}/payment-methods');
    if (response is List) {
      return response.map((data) => PaymentMethod.fromMap(data)).toList();
    }
    return [];
  }
  
  Future<Transaction> preparePayment(String billId, String paymentMethodId, String idempotencyKey) async {
    final payload = {
      'bill_id': billId,
      'payment_method_id': paymentMethodId,
      'idempotency_key': idempotencyKey,
    };
    
    final response = await _apiClient.post('/payments/prepare', data: payload);
    // Note: /prepare returns PaymentPrepareResponse, which maps to Transaction structurally,
    // or we can map it directly to a Transaction model for presentation.
    // The backend returns: transaction_id, bill_id, amount, currency, status.
    return Transaction(
      id: response['transaction_id'],
      biller: 'Unknown', // Not returned by prepare endpoint, details can be refetched if needed
      amount: response['amount'].toString(),
      currency: response['currency'],
      status: response['status'],
      createdAt: DateTime.now(), // Estimate since prepare endpoint doesn't return created_at
    );
  }
}
