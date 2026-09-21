import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class ApiConfig {
  /// Resolves the backend base URL depending on the platform for local development.
  /// Android Emulator accesses host via 10.0.2.2.
  /// iOS Simulator accesses host via 127.0.0.1.
  /// Physical devices need the developer's LAN IP.
  static String get baseUrl {
    // If you are testing on a physical device, change this to your LAN IP (e.g., 'http://192.168.1.5:8000/api/v1')
    // DO NOT commit your personal LAN IP. Keep it as the default local configurations below.
    const String customLanIp = ''; 

    if (customLanIp.isNotEmpty) {
      return customLanIp;
    }

    if (kIsWeb) {
      return 'http://127.0.0.1:8000/api/v1';
    }

    if (Platform.isAndroid) {
      return 'http://10.0.2.2:8000/api/v1';
    } else {
      return 'http://127.0.0.1:8000/api/v1';
    }
  }

  /// The hardcoded deterministic user ID for Phase 5 development.
  /// This bypasses the need for authentication in this phase.
  /// IMPORTANT: This is marked development-only and must be replaced 
  /// with authenticated identity (e.g., JWT extraction) in later phases.
  static const String devUserId = '11111111-1111-1111-1111-111111111111';
}
