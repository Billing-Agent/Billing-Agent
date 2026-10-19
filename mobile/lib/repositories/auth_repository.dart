import '../services/api_client.dart';
import '../core/storage/token_storage.dart';
import '../core/errors/app_errors.dart';
import '../models/auth_response.dart';
import '../models/user.dart';

class AuthRepository {
  final ApiClient _apiClient;
  final TokenStorage _tokenStorage;

  AuthRepository({
    required ApiClient apiClient,
    required TokenStorage tokenStorage,
  })  : _apiClient = apiClient,
        _tokenStorage = tokenStorage;

  Future<AuthResponse> login(String email, String password) async {
    try {
      final response = await _apiClient.post(
        '/auth/login',
        data: {
          'email': email,
          'password': password,
        },
      );

      final authResponse = AuthResponse.fromJson(response as Map<String, dynamic>);
      if (authResponse.accessToken.isEmpty) {
        throw ServerError('Received invalid access token from server.');
      }

      await _tokenStorage.saveToken(authResponse.accessToken);
      _apiClient.setToken(authResponse.accessToken);

      final user = await getCurrentUser();
      return AuthResponse(
        accessToken: authResponse.accessToken,
        tokenType: authResponse.tokenType,
        user: user,
      );
    } catch (e) {
      await _tokenStorage.deleteToken();
      _apiClient.clearToken();
      rethrow;
    }
  }

  Future<User> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final response = await _apiClient.post(
      '/auth/register',
      data: {
        'name': name,
        'email': email,
        'password': password,
      },
    );

    final map = response as Map<String, dynamic>;
    final userMap = (map['user'] is Map<String, dynamic>)
        ? map['user'] as Map<String, dynamic>
        : map;
    return User.fromMap(userMap);
  }

  Future<User> getCurrentUser() async {
    final response = await _apiClient.get('/auth/me');
    return User.fromMap(response as Map<String, dynamic>);
  }

  Future<void> logout() async {
    await _tokenStorage.deleteToken();
    _apiClient.clearToken();
  }
}
