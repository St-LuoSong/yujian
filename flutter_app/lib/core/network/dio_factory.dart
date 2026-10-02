import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import 'session_interceptor.dart';

/// Refresh endpoint, relative to the configured API base url.
const String refreshPath = '/auth/refresh';

/// Dio without any interceptor. Used for the refresh call itself so a failing
/// refresh cannot re-enter the session interceptor.
Dio buildBareDio(AppConfig config) => Dio(_baseOptions(config));

/// Dio used by repositories: carries the session and logs requests in debug.
Dio buildApiDio(
    {required AppConfig config,
    required SessionInterceptor sessionInterceptor}) {
  final dio = buildBareDio(config);
  dio.interceptors.add(sessionInterceptor);
  if (kDebugMode) {
    // Headers and bodies stay out of the log on purpose: they carry the access
    // token and the anonymous trial token.
    dio.interceptors.add(
      LogInterceptor(
        request: true,
        requestHeader: false,
        requestBody: false,
        responseHeader: false,
        responseBody: false,
        error: true,
      ),
    );
  }
  return dio;
}

BaseOptions _baseOptions(AppConfig config) => BaseOptions(
      baseUrl: config.apiBaseUrl,
      connectTimeout: config.connectTimeout,
      receiveTimeout: config.receiveTimeout,
      sendTimeout: config.sendTimeout,
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
      headers: const <String, Object>{'Accept': 'application/json'},
    );
