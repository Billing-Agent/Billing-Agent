import 'package:flutter/foundation.dart';

/// Configuration for PayHere Mobile SDK.
///
/// Handles configurable Merchant Secret provisioning for mobile sandbox and testing.
///
/// SECURITY & ARCHITECTURAL MODEL:
/// - The Merchant Secret is NOT committed to Git.
/// - It is an app-specific PayHere credential required by their Mobile SDK (`payhere_mobilesdk_flutter`)
///   passed in the native `paymentObject`.
/// - IMPORTANT: This value is NOT securely hidden from the compiled application. A determined
///   attacker can decompile the mobile binary and extract embedded constants or environment values.
/// - Because the client runtime environment cannot guarantee secret secrecy, financial success
///   is NEVER trusted from the mobile SDK callbacks (`onCompleted`).
/// - The backend-verified PayHere webhook callback (`/api/v1/payhere/callback` via `md5sig`)
///   remains the sole authoritative source of payment completion.
class PayHereConfig {
  /// PayHere Mobile App-Specific Merchant Secret loaded via compile-time environment flag.
  ///
  /// Supply during local sandbox run with:
  /// ```bash
  /// flutter run --dart-define=PAYHERE_MERCHANT_SECRET=your_sandbox_secret
  /// ```
  static const String _envSecret = String.fromEnvironment(
    'PAYHERE_MERCHANT_SECRET',
    defaultValue: '',
  );

  /// In-memory override for local sandbox testing or automated test execution.
  static String? _overrideSecret;

  /// Returns the effective Merchant Secret.
  ///
  /// Resolution order:
  /// 1. Dynamic in-memory override (e.g. set in local test harness)
  /// 2. `--dart-define=PAYHERE_MERCHANT_SECRET` compile-time flag
  /// 3. Empty string if not supplied
  static String get merchantSecret => _overrideSecret ?? _envSecret;

  /// Whether a non-empty merchant secret is available.
  static bool get hasMerchantSecret => merchantSecret.isNotEmpty;

  /// Sets a temporary merchant secret for sandbox testing or automated test verification.
  ///
  /// Do not use to store persistent hardcoded credentials in source control.
  static void setTemporarySecret(String? secret) {
    _overrideSecret = secret;
  }

  /// Clears any temporary in-memory override.
  @visibleForTesting
  static void reset() {
    _overrideSecret = null;
  }
}
