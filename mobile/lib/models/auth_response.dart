import 'user.dart';

class AuthResponse {
  final String accessToken;
  final String tokenType;
  final User user;

  const AuthResponse({
    required this.accessToken,
    required this.tokenType,
    required this.user,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      accessToken: (json['access_token'] ?? json['accessToken'] ?? '').toString(),
      tokenType: (json['token_type'] ?? json['tokenType'] ?? 'bearer').toString(),
      user: User.fromMap(json['user'] as Map<String, dynamic>),
    );
  }
}
