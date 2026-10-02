import 'package:flutter/foundation.dart';

/// Central runtime configuration for the APK.
///
/// Endpoint resolution rules:
///
/// 1. An explicit `--dart-define=API_BASE_URL=...` always wins.
/// 2. Debug / profile builds fall back to the Android emulator loopback host
///    so a locally started Spring Boot instance is reachable out of the box.
/// 3. Release builds have **no** HTTP fallback. Shipping a release APK that
///    silently talks to a plaintext local endpoint would contradict
///    `app/src/main/res/xml/network_security_config.xml`, which blocks
///    cleartext traffic outside debug builds.
///
/// When [hasEndpoint] is false the client reports a configuration failure
/// instead of pretending the server answered.
class AppConfig {
  const AppConfig({
    required this.apiBaseUrl,
    required this.connectTimeout,
    required this.receiveTimeout,
    required this.sendTimeout,
  });

  factory AppConfig.resolve({String? runtimeEndpoint}) {
    final String? stored = runtimeEndpoint == null
        ? null
        : normalizeUserEndpoint(runtimeEndpoint);
    final resolved = _override.isNotEmpty
        ? _override
        : (stored ?? (kReleaseMode ? '' : _emulatorBaseUrl));
    return AppConfig(
      apiBaseUrl: _normalize(resolved),
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 20),
    );
  }

  /// Compile time override: `--dart-define=API_BASE_URL=https://host/api`.
  ///
  /// Must stay a top level `const` so the value is resolved by the compiler
  /// rather than at runtime.
  static const String _override = String.fromEnvironment('API_BASE_URL');

  /// Host loopback as seen from the Android emulator.
  static const String _emulatorBaseUrl = 'http://10.0.2.2:8080/api';

  final String apiBaseUrl;
  final Duration connectTimeout;
  final Duration receiveTimeout;
  final Duration sendTimeout;

  /// False when a release build was produced without `API_BASE_URL`.
  bool get hasEndpoint => apiBaseUrl.isNotEmpty;

  /// True when the address was fixed at compile time and must not be changed
  /// from the settings page.
  bool get lockedByBuild => _override.isNotEmpty;

  /// True when the endpoint uses plain HTTP. Release builds reject this.
  bool get isPlaintext => apiBaseUrl.startsWith('http://');

  /// Creates a copy with a user-editable server address.
  AppConfig withEndpoint(String value) {
    final normalized = normalizeUserEndpoint(value);
    if (normalized == null) {
      throw const FormatException('服务器地址格式不正确');
    }
    return AppConfig(
      apiBaseUrl: normalized,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      sendTimeout: sendTimeout,
    );
  }

  /// Normalizes an address typed by a user.
  ///
  /// A bare host is treated as HTTPS; an empty path becomes `/api`. Release
  /// builds reject plaintext HTTP because the Android network security config
  /// would block it anyway, and accepting it here would only produce a
  /// confusing "saved but unreachable" state.
  static String? normalizeUserEndpoint(String value) {
    var raw = value.trim();
    if (raw.isEmpty) {
      return null;
    }
    if (!raw.contains('://')) {
      raw = 'https://$raw';
    }
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    if (kReleaseMode && uri.scheme != 'https') {
      return null;
    }
    var path = uri.path;
    if (path.isEmpty || path == '/') {
      path = '/api';
    }
    while (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://$host$port$path';
  }

  static String _normalize(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }

  /// True when [host] names the machine that is running the app itself.
  ///
  /// Inside the Android emulator `localhost` is the emulated device, **not**
  /// the developer machine, so a loopback URL that works in a desktop browser
  /// shows a broken image on the phone.
  static bool isLoopbackHost(String host) {
    final value = host.toLowerCase();
    return value == 'localhost' ||
        value == '127.0.0.1' ||
        value == '0.0.0.0' ||
        value == '::1' ||
        value == '[::1]' ||
        value.endsWith('.localhost');
  }

  /// The scheme://host:port part of [uri], without any path.
  static String _originOf(Uri uri) {
    final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
    return uri.hasPort
        ? '${uri.scheme}://$host:${uri.port}'
        : '${uri.scheme}://$host';
  }

  /// Rewrites a media URL returned by the backend so *this* device can load it.
  ///
  /// The operator console uploads attraction photos from a desktop browser, so
  /// the backend derives the public URL from that request and answers with
  /// `http://localhost:8080/media/...`. That URL is correct in the browser and
  /// wrong on the phone. Instead of asking the operator to keep a second base
  /// URL in sync, the loopback host is swapped for the host this client already
  /// talks to for the API.
  ///
  /// Returned unchanged:
  /// - an empty value, or any URL whose host is already reachable;
  /// - photos hosted elsewhere (the bundled catalogue uses remote https URLs);
  /// - builds without an endpoint, where there is nothing better to offer.
  ///
  /// Also accepted and joined onto the API origin:
  /// - a path only URL such as `/media/abc.jpg`;
  /// - a protocol relative URL such as `//localhost:8080/media/abc.jpg`.
  String resolveMediaUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty || !hasEndpoint) {
      return value;
    }
    final api = Uri.tryParse(apiBaseUrl);
    if (api == null || api.host.isEmpty) {
      return value;
    }
    final media = Uri.tryParse(value);
    if (media == null) {
      return value;
    }
    if (media.hasScheme) {
      if (!isLoopbackHost(media.host)) {
        return value;
      }
    } else if (media.host.isNotEmpty && !isLoopbackHost(media.host)) {
      // Protocol relative: only a loopback host is safe to re-point.
      return value;
    }
    if (media.path.isEmpty) {
      return value;
    }
    final query = media.hasQuery ? '?${media.query}' : '';
    return _originOf(api) + media.path + query;
  }
}
