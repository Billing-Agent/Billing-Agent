import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../core/constants/api_config.dart';
import '../core/errors/app_errors.dart';

/// Real HTTP API Client for FastAPI Integration.
class ApiClient {
  final http.Client _client;

  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  /// Map HTTP status codes to AppError exceptions.
  void _handleResponseError(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    final message = _extractErrorMessage(response.body);

    switch (response.statusCode) {
      case 400:
        throw ValidationError(message ?? "Please check the bill or payment details.");
      case 404:
        throw NetworkError("Bill not found."); // Map 404 cleanly
      case 409:
        throw ServerError("This payment request is already being processed.");
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
      return json['detail']?.toString();
    } catch (_) {
      return null;
    }
  }

  /// Headers including the dev-only x-user-id
  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        // Pass dev user id to bypass missing authentication phase
        'x-user-id': ApiConfig.devUserId,
      };

  Future<dynamic> get(String path) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}$path');
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));
          
      _handleResponseError(response);
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
      final response = await _client
          .post(uri, headers: _headers, body: data != null ? jsonEncode(data) : null)
          .timeout(const Duration(seconds: 10));

      _handleResponseError(response);
      return jsonDecode(response.body);
    } on TimeoutException {
      throw NetworkError("Unable to connect. Please check your connection.");
    } on http.ClientException {
      throw NetworkError("Unable to connect. Please check your connection.");
    }
  }
}
