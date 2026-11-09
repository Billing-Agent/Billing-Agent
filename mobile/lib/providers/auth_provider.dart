import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/storage/token_storage.dart';
import '../models/auth_state.dart';
import '../repositories/auth_repository.dart';
import '../repositories/bill_repository.dart';
import '../services/api_client.dart';
import '../core/errors/app_errors.dart';

export '../core/storage/token_storage.dart' show tokenStorageProvider;

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final tokenStorage = ref.watch(tokenStorageProvider);
  return AuthRepository(apiClient: apiClient, tokenStorage: tokenStorage);
});

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  final storage = ref.watch(tokenStorageProvider);
  final apiClient = ref.watch(apiClientProvider);
  final notifier = AuthNotifier(
      repository: repository, tokenStorage: storage, apiClient: apiClient);
  apiClient.onUnauthorized = () {
    notifier.handleUnauthorized();
  };
  return notifier;
});

/// A unique lifetime for one authenticated mobile session.
///
/// A new instance is created after every logout/login boundary, even when the
/// same account signs in again. User-scoped providers and asynchronous work use
/// object identity plus [isActive] to reject state from superseded sessions.
class AuthenticatedSession {
  final String userId;
  bool _isActive = true;

  AuthenticatedSession(this.userId);

  bool get isActive => _isActive;

  void _invalidate() {
    _isActive = false;
  }
}

final authenticatedSessionProvider = Provider<AuthenticatedSession?>((ref) {
  final authState = ref.watch(authProvider);
  final user = authState.user;
  if (!authState.isAuthenticated || user == null) {
    return null;
  }

  final session = AuthenticatedSession(user.id);
  ref.onDispose(session._invalidate);
  return session;
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
      final user = authResponse.user;
      if (user == null) {
        throw ServerError('User profile could not be loaded.');
      }
      state = AuthState.authenticated(user);
    } catch (e) {
      await _tokenStorage.deleteToken();
      _apiClient.clearToken();
      final message = e.toString();
      state = AuthState.unauthenticated(message);
      rethrow;
    }
  }

  Future<void> register(String name, String email, String password) async {
    state = AuthState.loading();
    try {
      await _repository.register(
        name: name,
        email: email,
        password: password,
      );
      await login(email, password);
    } catch (e) {
      await _tokenStorage.deleteToken();
      _apiClient.clearToken();
      final message = e.toString();
      state = AuthState.unauthenticated(message);
      rethrow;
    }
  }

  Future<void> logout() async {
    // End the mobile session before secure-storage I/O so late requests and SDK
    // callbacks cannot update user-scoped state during logout.
    state = AuthState.unauthenticated();
    _apiClient.clearToken();
    await _repository.logout();
  }

  Future<void> handleUnauthorized() async {
    if (state.status == AuthStatus.authenticated) {
      await logout();
    }
  }
}
