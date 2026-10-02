import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Narrow seam over the platform keystore.
///
/// The session layer is where sign in, token rotation and the anonymous
/// handover meet, so it has to be testable without a device. This interface
/// keeps that logic free of the plugin.
abstract interface class SecureKeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// Production adapter: the platform keystore, encrypted on Android.
class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  FlutterSecureKeyValueStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Immutable view of the stored session.
class SessionSnapshot {
  const SessionSnapshot({
    this.accessToken,
    this.refreshToken,
    this.anonymousToken,
  });

  final String? accessToken;
  final String? refreshToken;
  final String? anonymousToken;

  bool get hasUser => accessToken != null && accessToken!.isNotEmpty;

  bool get hasAnonymous => anonymousToken != null && anonymousToken!.isNotEmpty;

  bool get isEmpty => !hasUser && !hasAnonymous;
}

/// Secure storage for credentials only.
///
/// Passwords are never stored. Tokens live in the platform keystore and are
/// kept in memory for the lifetime of the process, so the request interceptor
/// does not hit the keystore on every call.
class SessionStore {
  SessionStore({SecureKeyValueStore? storage})
      : _storage = storage ?? FlutterSecureKeyValueStore();

  /// Header used for anonymous trial sessions.
  static const String anonymousHeader = 'X-Anonymous-Token';

  /// Upper bound for a single keystore round trip.
  ///
  /// The platform keystore can wedge (a cold emulator or a broken key store
  /// generates RSA keys on first use). Every caller of this class treats
  /// storage failures as non fatal, and a hang has to behave the same way:
  /// otherwise signing in would wait on the keystore for ever.
  static const Duration storageTimeout = Duration(seconds: 4);

  static const String _accessKey = 'yujian.access_token';
  static const String _refreshKey = 'yujian.refresh_token';
  static const String _anonymousKey = 'yujian.anonymous_token';

  final SecureKeyValueStore _storage;
  SessionSnapshot? _cached;

  Future<SessionSnapshot> read() async {
    final cached = _cached;
    if (cached != null) {
      return cached;
    }
    final snapshot = SessionSnapshot(
      accessToken: await _read(_accessKey),
      refreshToken: await _read(_refreshKey),
      anonymousToken: await _read(_anonymousKey),
    );
    _cached = snapshot;
    return snapshot;
  }

  /// Stores the anonymous trial token returned by the backend.
  Future<void> saveAnonymousToken(String token) async {
    if (token.isEmpty) {
      return;
    }
    final current = await read();
    if (current.anonymousToken == token) {
      return;
    }
    await _write(_anonymousKey, token);
    _cached = SessionSnapshot(
      accessToken: current.accessToken,
      refreshToken: current.refreshToken,
      anonymousToken: token,
    );
  }

  /// Stores a freshly issued user session. The anonymous token is kept so the
  /// client can still merge the trial trip after signing in.
  Future<void> saveUserSession({
    required String accessToken,
    required String refreshToken,
  }) async {
    final current = await read();
    await _write(_accessKey, accessToken);
    await _write(_refreshKey, refreshToken);
    _cached = SessionSnapshot(
      accessToken: accessToken,
      refreshToken: refreshToken,
      anonymousToken: current.anonymousToken,
    );
  }

  /// Drops the user session after a failed refresh or an explicit sign out.
  ///
  /// [ifToken] guards the one dangerous call site: `restore()` rejects a stale
  /// token, but that rejection may arrive *after* the user signed in again.
  /// Clearing unconditionally would then delete the brand new credentials and
  /// sign the user straight back out. With [ifToken] set, the session is only
  /// dropped when the stored access token is still the one that failed.
  Future<void> clearUserSession({String? ifToken}) async {
    final current = await read();
    if (ifToken != null &&
        current.accessToken != null &&
        current.accessToken != ifToken) {
      return;
    }
    await _delete(_accessKey);
    await _delete(_refreshKey);
    _cached = SessionSnapshot(anonymousToken: current.anonymousToken);
  }

  /// Drops every credential, including the anonymous trial token.
  Future<void> clearAll() async {
    await _delete(_accessKey);
    await _delete(_refreshKey);
    await _delete(_anonymousKey);
    _cached = const SessionSnapshot();
  }

  /// Drops the anonymous trial token after it has been merged into an account.
  ///
  /// A converted session can no longer authenticate, so keeping the token would
  /// make later requests fail instead of using the user session.
  Future<void> clearAnonymousToken() async {
    final current = await read();
    await _delete(_anonymousKey);
    _cached = SessionSnapshot(
      accessToken: current.accessToken,
      refreshToken: current.refreshToken,
    );
  }

  Future<String?> _read(String key) async {
    try {
      final value = await _storage.read(key).timeout(storageTimeout);
      return value == null || value.isEmpty ? null : value;
    } on Exception {
      // A corrupted keystore entry must not break the whole app. Treat it as
      // "not signed in"; the next successful write recreates the value.
      return null;
    }
  }

  Future<void> _write(String key, String value) async {
    try {
      await _storage.write(key, value).timeout(storageTimeout);
    } on Exception {
      // Storage failures are non fatal: the in-memory snapshot still keeps the
      // current run working, the user is simply asked to sign in again later.
    }
  }

  Future<void> _delete(String key) async {
    try {
      await _storage.delete(key).timeout(storageTimeout);
    } on Exception {
      // Ignore: the cached snapshot is cleared regardless.
    }
  }
}
