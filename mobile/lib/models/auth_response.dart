import 'user.dart';

class AuthResponse {
  final String accessToken;
  final String tokenType;
  final User? user;

  const AuthResponse({
    required this.accessToken,
    required this.tokenType,
    this.user,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      accessToken: (json['access_token'] ?? json['accessToken'] ?? '').toString(),
      tokenType: (json['token_type'] ?? json['tokenType'] ?? 'bearer').toString(),
      user: json['user'] != null && json['user'] is Map<String, dynamic>
          ? User.fromMap(json['user'] as Map<String, dynamic>)
          : null,
    );
  }

  AuthResponse copyWith({
    String? accessToken,
    String? tokenType,
    User? user,
  }) {
    return AuthResponse(
      accessToken: accessToken ?? this.accessToken,
      tokenType: tokenType ?? this.tokenType,
      user: user ?? this.user,
    );
  }
}
