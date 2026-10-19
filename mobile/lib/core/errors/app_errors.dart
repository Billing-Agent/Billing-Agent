abstract class AppError implements Exception {
  final String message;
  AppError(this.message);

  @override
  String toString() => message;
}

class NetworkError extends AppError {
  NetworkError([super.message = "Please check your internet connection."]);
}

class ServerError extends AppError {
  ServerError([super.message = "A server error occurred. Please try again later."]);
}

class ValidationError extends AppError {
  ValidationError([super.message = "Invalid input provided."]);
}

class UnauthorizedError extends AppError {
  UnauthorizedError([super.message = "Unauthorized. Please log in again."]);
}

class UnknownError extends AppError {
  UnknownError([super.message = "An unexpected error occurred."]);
}

