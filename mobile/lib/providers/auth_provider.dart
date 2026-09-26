import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/storage/token_storage.dart';
import '../models/auth_state.dart';
import '../repositories/auth_repository.dart';
import '../repositories/bill_repository.dart';
import '../services/api_client.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) {
  return TokenStorage();
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final tokenStorage = ref.watch(tokenStorageProvider);
  return AuthRepository(apiClient: apiClient, tokenStorage: tokenStorage);
});

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  final storage = ref.watch(tokenStorageProvider);
  final apiClient = ref.watch(apiClientProvider);
  return AuthNotifier(repository: repository, tokenStorage: storage, apiClient: apiClient);
});

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repository;
  final TokenStorage _tokenStorage;
  final ApiClient _apiClient;

  AuthNotifier({
    required AuthRepository repository,
    required TokenStorage tokenStorage,
    required ApiClient apiClient,
  })  : _repository = repository,
        _tokenStorage = tokenStorage,
        _apiClient = apiClient,
        super(AuthState.initial()) {
    checkAuthStatus();
  }

  Future<void> checkAuthStatus() async {
    state = AuthState.loading();
    try {
      final token = await _tokenStorage.getToken();
      if (token == null || token.isEmpty) {
        _apiClient.clearToken();
        state = AuthState.unauthenticated();
        return;
      }

      _apiClient.setToken(token);
      final user = await _repository.getCurrentUser();
      state = AuthState.authenticated(user);
    } catch (_) {
      await _tokenStorage.deleteToken();
      _apiClient.clearToken();
      state = AuthState.unauthenticated();
    }
  }

  Future<void> login(String email, String password) async {
    state = AuthState.loading();
    try {
      final authResponse = await _repository.login(email, password);
      state = AuthState.authenticated(authResponse.user);
    } catch (e) {
      final message = e.toString();
      state = AuthState.unauthenticated(message);
      rethrow;
    }
  }

  Future<void> register(String name, String email, String password) async {
    state = AuthState.loading();
    try {
      final authResponse = await _repository.register(
        name: name,
        email: email,
        password: password,
      );
      state = AuthState.authenticated(authResponse.user);
    } catch (e) {
      final message = e.toString();
      state = AuthState.unauthenticated(message);
      rethrow;
    }
  }

  Future<void> logout() async {
    await _repository.logout();
    state = AuthState.unauthenticated();
  }

  Future<void> handleUnauthorized() async {
    await logout();
  }
}
