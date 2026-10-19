import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/bill.dart';
import '../services/api_client.dart';
import '../core/storage/token_storage.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  final tokenStorage = ref.watch(tokenStorageProvider);
  return ApiClient(tokenStorage: tokenStorage);
});

final billRepositoryProvider = Provider<BillRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return BillRepository(apiClient);
});

class BillRepository {
  final ApiClient _apiClient;

  BillRepository(this._apiClient);

  Future<List<Bill>> getUserBills() async {
    final response = await _apiClient.get('/me/bills');
    
    // Parse the list
    if (response is List) {
      return response.map((data) => Bill.fromMap(data)).toList();
    }
    return [];
  }

  Future<Bill?> getBillById(String id) async {
    final response = await _apiClient.get('/bills/$id');
    if (response != null) {
      return Bill.fromMap(response);
    }
    return null;
  }
}