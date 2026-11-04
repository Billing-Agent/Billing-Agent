import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/agent_response.dart';
import '../services/api_client.dart';
import 'bill_repository.dart'; // Reuses apiClientProvider

final agentRepositoryProvider = Provider<AgentRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return AgentRepository(apiClient);
});

class AgentRepository {
  final ApiClient _apiClient;

  AgentRepository(this._apiClient);

  /// Send a natural language message to the Billing Assistant.
  Future<AgentChatResponse> sendMessage(String message) async {
    final response = await _apiClient.post(
      '/agent/chat',
      data: {'message': message},
    );
    return AgentChatResponse.fromMap(response as Map<String, dynamic>);
  }

  /// Deterministically confirms a payment using ONLY the backend-issued confirmation_id.
  ///
  /// CRITICAL SECURITY:
  /// NEVER include amount, user_id, bill_id, payment_method_id, or currency in this request.
  /// The backend revalidates all financial facts from its authoritative store.
  Future<AgentPaymentConfirmResponse> confirmPayment(String confirmationId) async {
    final payload = {
      'confirmation_id': confirmationId,
    };
    final response = await _apiClient.post(
      '/agent/payments/confirm',
      data: payload,
    );
    return AgentPaymentConfirmResponse.fromMap(response as Map<String, dynamic>);
  }
}
