import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../core/constants/api_config.dart';
import '../core/errors/app_errors.dart';
import '../core/storage/token_storage.dart';

/// Real HTTP API Client for FastAPI Integration.
class ApiClient {
  final http.Client _client;
  final TokenStorage? _tokenStorage;
  String? _token;
  int _authGeneration = 0;
  void Function()? onUnauthorized;

  ApiClient({
    http.Client? client,
    TokenStorage? tokenStorage,
    this.onUnauthorized,
  })  : _client = client ?? http.Client(),
        _tokenStorage = tokenStorage;

  void setToken(String token) {
    _token = token;
    _authGeneration++;
  }

  void clearToken() {
    _token = null;
    _authGeneration++;
  }

  /// Map HTTP status codes to AppError exceptions.
  void _handleResponseError(
    http.Response response, {
    String? path,
    required int requestAuthGeneration,
  }) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    final message = _extractErrorMessage(response.body);

    switch (response.statusCode) {
      case 400:
        throw ValidationError(
            message ?? "Please check the bill or payment details.");
      case 401:
        final isAuthEndpoint = path != null &&
            (path.endsWith('/auth/login') || path.endsWith('/auth/register'));
        if (!isAuthEndpoint && requestAuthGeneration == _authGeneration) {
          onUnauthorized?.call();
        }
        throw UnauthorizedError(
            message ?? "Unauthorized. Please log in again.");
      case 404:
        throw NetworkError("Bill not found."); // Map 404 cleanly
      case 409:
        throw ServerError("This payment request is already being processed.");
      case 422:
        throw ValidationError(message ?? "Invalid request parameters.");
      default:
        if (response.statusCode >= 500) {
          throw ServerError("Something went wrong. Please try again.");
        }
        throw UnknownError(message ?? "An unexpected error occurred.");
    }
  }

  String? _extractErrorMessage(String body) {
    try {
      final json = jsonDecode(body);
      final detail = json['detail'];
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map && first.containsKey('msg')) {
          return first['msg']?.toString();
        }
      }
      return detail?.toString();
    } catch (_) {
      return null;
    }
  }

  /// Headers including Bearer token from in-memory token or persistent token storage
  Future<Map<String, String>> _buildHeaders() async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if ((_token == null || _token!.isEmpty) && _tokenStorage != null) {
      final storageReadGeneration = _authGeneration;
      final storedToken = await _tokenStorage.getToken();
      if (storageReadGeneration == _authGeneration && storedToken != _token) {
        _token = storedToken;
        _authGeneration++;
      }
    }

    if (_token != null && _token!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  Future<dynamic> get(String path) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}$path');
      final headers = await _buildHeaders();
      final requestAuthGeneration = _authGeneration;
      final response = await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 30));

      _handleResponseError(
        response,
        path: path,
        requestAuthGeneration: requestAuthGeneration,
      );
      return jsonDecode(response.body);
    } on TimeoutException {
      throw NetworkError("Unable to connect. Please check your connection.");
    } on http.ClientException {
      throw NetworkError("Unable to connect. Please check your connection.");
    }
  }

  Future<dynamic> post(String path, {Map<String, dynamic>? data}) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}$path');
      final headers = await _buildHeaders();
      final requestAuthGeneration = _authGeneration;
      final response = await _client
          .post(uri,
              headers: headers, body: data != null ? jsonEncode(data) : null)
          .timeout(const Duration(seconds: 30));

      _handleResponseError(
        response,
        path: path,
        requestAuthGeneration: requestAuthGeneration,
      );
      return jsonDecode(response.body);
    } on TimeoutException {
      throw NetworkError("Unable to connect. Please check your connection.");
    } on http.ClientException {
      throw NetworkError("Unable to connect. Please check your connection.");
    }
  }
}
