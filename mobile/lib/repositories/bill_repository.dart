import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/bill.dart';
import '../services/api_client.dart';
import '../core/constants/api_config.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient();
});

final billRepositoryProvider = Provider<BillRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return BillRepository(apiClient);
});

class BillRepository {
  final ApiClient _apiClient;

  BillRepository(this._apiClient);

  Future<List<Bill>> getUserBills() async {
    // Uses the dev user id to fetch bills
    final response = await _apiClient.get('/users/${ApiConfig.devUserId}/bills');
    
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
