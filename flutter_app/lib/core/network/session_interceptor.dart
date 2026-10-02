import 'package:dio/dio.dart';

import '../storage/session_store.dart';

/// Attaches the current session to every request, captures the anonymous token
/// the backend hands out, and performs a single-flight refresh when a user
/// access token expires.
///
/// A [QueuedInterceptor] is used on purpose: it serializes the refresh so five
/// parallel 401 responses trigger one refresh call instead of five.
class SessionInterceptor extends QueuedInterceptor {
  SessionInterceptor({
    required SessionStore store,
    required Dio refreshClient,
    required String refreshPath,
  })  : _store = store,
        _refreshClient = refreshClient,
        _refreshPath = refreshPath;

  /// Marks a request that already consumed one refresh attempt, so a second
  /// 401 cannot loop forever.
  static const String retriedFlag = 'yujian.session.retried';

  final SessionStore _store;

  /// Bare Dio without this interceptor, used to call the refresh endpoint.
  final Dio _refreshClient;

  final String _refreshPath;

  Future<bool>? _refreshInFlight;

  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    _applySession(options, await _store.read());
    handler.next(options);
  }

  @override
  void onResponse(
      Response<dynamic> response, ResponseInterceptorHandler handler) async {
    await _captureAnonymousToken(response.headers);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    await _captureAnonymousToken(err.response?.headers);
    if (!_shouldRefresh(err)) {
      handler.next(err);
      return;
    }
    final refreshed = await _refresh();
    if (!refreshed) {
      await _store.clearUserSession();
      handler.next(err);
      return;
    }
    try {
      final options = err.requestOptions..extra[retriedFlag] = true;
      options.headers.remove('Authorization');
      _applySession(options, await _store.read());
      handler.resolve(await _refreshClient.fetch<dynamic>(options));
    } on Object {
      handler.next(err);
    }
  }

  void _applySession(RequestOptions options, SessionSnapshot session) {
    if (session.hasUser) {
      options.headers['Authorization'] = 'Bearer ${session.accessToken}';
      return;
    }
    if (session.hasAnonymous) {
      options.headers[SessionStore.anonymousHeader] = session.anonymousToken;
    }
  }

  Future<void> _captureAnonymousToken(Headers? headers) async {
    final token = headers?.value(SessionStore.anonymousHeader);
    if (token == null || token.isEmpty) {
      return;
    }
    await _store.saveAnonymousToken(token);
  }

  bool _shouldRefresh(DioException error) {
    if (error.response?.statusCode != 401) {
      return false;
    }
    if (error.requestOptions.extra[retriedFlag] == true) {
      return false;
    }
    return !error.requestOptions.path.contains(_refreshPath);
  }

  /// Deduplicates concurrent refreshes; exactly one HTTP call is issued while
  /// several requests are waiting for a new access token.
  Future<bool> _refresh() {
    final inFlight = _refreshInFlight;
    if (inFlight != null) {
      return inFlight;
    }
    final future = _performRefresh();
    _refreshInFlight = future.whenComplete(() => _refreshInFlight = null);
    return _refreshInFlight!;
  }

  Future<bool> _performRefresh() async {
    final refreshToken = (await _store.read()).refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      return false;
    }
    try {
      final response = await _refreshClient.post<Map<String, dynamic>>(
        _refreshPath,
        data: <String, Object?>{'refreshToken': refreshToken},
      );
      final data = response.data;
      final accessToken = data?['accessToken']?.toString();
      final rotatedRefreshToken = data?['refreshToken']?.toString();
      if (accessToken == null ||
          accessToken.isEmpty ||
          rotatedRefreshToken == null ||
          rotatedRefreshToken.isEmpty) {
        return false;
      }
      await _store.saveUserSession(
          accessToken: accessToken, refreshToken: rotatedRefreshToken);
      return true;
    } on Object {
      return false;
    }
  }
}
