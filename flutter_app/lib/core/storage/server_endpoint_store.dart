import 'dart:async';

import 'session_store.dart';

/// Persists the user-selected API base address.
///
/// The address is not a credential, but it is kept in the same platform
/// keystore as tokens: it avoids introducing a second storage dependency and
/// keeps an accidental process kill from losing a just-entered endpoint.
class ServerEndpointStore {
  ServerEndpointStore({SecureKeyValueStore? storage})
      : _storage = storage ?? FlutterSecureKeyValueStore();

  static const String _key = 'yujian.api_base_url';

  final SecureKeyValueStore _storage;

  Future<String?> read() async {
    try {
      final value = await _storage.read(_key).timeout(
            const Duration(seconds: 4),
          );
      return value == null || value.isEmpty ? null : value;
    } on Object {
      return null;
    }
  }

  Future<void> write(String value) async {
    try {
      await _storage.write(_key, value).timeout(
            const Duration(seconds: 4),
          );
    } on Object {
      // A failed write must not crash the settings page. The in-memory
      // AppConfig still applies for this process; the next restart may fall
      // back to the build-time or emulator endpoint.
    }
  }

  Future<void> clear() async {
    try {
      await _storage.delete(_key).timeout(
            const Duration(seconds: 4),
          );
    } on Object {
      // Same non-fatal policy as write().
    }
  }
}
