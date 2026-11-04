import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/agent_response.dart';
import '../repositories/agent_repository.dart';

final agentServiceProvider = Provider<AgentService>((ref) {
  final repository = ref.watch(agentRepositoryProvider);
  return AgentService(repository);
});

class AgentService {
  final AgentRepository _repository;

  AgentService(this._repository);

  Future<AgentChatResponse> sendMessage(String message) {
    return _repository.sendMessage(message);
  }

  Future<AgentPaymentConfirmResponse> confirmPayment(String confirmationId) {
    return _repository.confirmPayment(confirmationId);
  }
}
