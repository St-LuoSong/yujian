import 'dart:io';

import 'package:dio/dio.dart';

/// Stable, user facing error categories.
///
/// Widgets switch on [ApiFailureKind] instead of inspecting Dio exceptions, so
/// retry and "需要登录" affordances stay consistent across screens.
enum ApiFailureKind {
  /// The client itself is misconfigured, for example a release build produced
  /// without `API_BASE_URL`.
  configuration,

  /// The device could not reach the server.
  network,

  /// The request timed out.
  timeout,

  /// The request was cancelled by the caller.
  cancelled,

  /// Authentication is missing, expired or invalid.
  unauthorized,

  /// The caller is authenticated but not allowed to perform the action.
  forbidden,

  /// The resource does not exist or is not owned by the caller.
  notFound,

  /// A uniqueness or state conflict.
  conflict,

  /// The payload was rejected by validation.
  validation,

  /// Rate limiting or anonymous trial exhaustion.
  rateLimited,

  /// The server failed to handle an otherwise valid request.
  server,

  /// The response could not be mapped onto the client model.
  parse,

  /// Anything not covered above.
  unknown,
}

/// Normalized transport failure.
///
/// The Spring Boot backend answers with `{code, message, timestamp}`, so
/// [code] and [message] come from the backend whenever it replied, and are
/// replaced with a neutral client message otherwise.
class ApiFailure implements Exception {
  const ApiFailure({
    required this.kind,
    required this.message,
    this.code,
    this.statusCode,
    this.requestId,
    this.cause,
  });

  factory ApiFailure.configuration(String message) =>
      ApiFailure(kind: ApiFailureKind.configuration, message: message);

  factory ApiFailure.parse(Object cause) => ApiFailure(
        kind: ApiFailureKind.parse,
        message: '返回数据与当前客户端版本不兼容，请稍后重试或更新应用。',
        cause: cause,
      );

  factory ApiFailure.fromDio(DioException error) {
    final status = error.response?.statusCode;
    final envelope = _Envelope.from(error.response?.data);
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return ApiFailure(
          kind: ApiFailureKind.timeout,
          message: '网络响应超时，请检查网络后重试。',
          code: envelope.code,
          statusCode: status,
          requestId: envelope.requestId,
          cause: error,
        );
      case DioExceptionType.cancel:
        return ApiFailure(
          kind: ApiFailureKind.cancelled,
          message: '请求已取消。',
          code: envelope.code,
          statusCode: status,
          requestId: envelope.requestId,
          cause: error,
        );
      case DioExceptionType.badCertificate:
        return ApiFailure(
          kind: ApiFailureKind.network,
          message: '服务器证书校验失败，请确认服务地址可信。',
          code: envelope.code,
          statusCode: status,
          requestId: envelope.requestId,
          cause: error,
        );
      case DioExceptionType.connectionError:
        return ApiFailure(
          kind: ApiFailureKind.network,
          message: '无法连接服务器，请确认网络与服务地址后重试。',
          code: envelope.code,
          statusCode: status,
          requestId: envelope.requestId,
          cause: error,
        );
      case DioExceptionType.badResponse:
        return _fromResponse(status, envelope, error);
      case DioExceptionType.unknown:
        if (error.error is SocketException) {
          return ApiFailure(
            kind: ApiFailureKind.network,
            message: '无法连接服务器，请确认网络与服务地址后重试。',
            code: envelope.code,
            statusCode: status,
            requestId: envelope.requestId,
            cause: error,
          );
        }
        return ApiFailure(
          kind: ApiFailureKind.unknown,
          message: '请求失败，请稍后重试。',
          code: envelope.code,
          statusCode: status,
          requestId: envelope.requestId,
          cause: error,
        );
    }
  }

  final ApiFailureKind kind;

  /// Message safe to render in the UI.
  final String message;

  /// Backend error code, for example `TRIAL_LIMIT_REACHED`.
  final String? code;

  final int? statusCode;

  /// Correlation id for support, when the backend provides one.
  final String? requestId;

  /// Original exception, for debug logging only.
  final Object? cause;

  bool get isRetryable =>
      kind == ApiFailureKind.network ||
      kind == ApiFailureKind.timeout ||
      kind == ApiFailureKind.server ||
      kind == ApiFailureKind.rateLimited;

  bool get requiresLogin => kind == ApiFailureKind.unauthorized;

  bool get isTrialLimit => code == 'TRIAL_LIMIT_REACHED';

  @override
  String toString() =>
      'ApiFailure($kind, code: $code, status: $statusCode, message: $message)';

  static ApiFailure _fromResponse(
      int? status, _Envelope envelope, DioException error) {
    final kind = switch (status) {
      401 => ApiFailureKind.unauthorized,
      403 => ApiFailureKind.forbidden,
      404 => ApiFailureKind.notFound,
      409 => ApiFailureKind.conflict,
      400 || 422 => ApiFailureKind.validation,
      429 => ApiFailureKind.rateLimited,
      final int code when code >= 500 => ApiFailureKind.server,
      _ => ApiFailureKind.unknown,
    };
    return ApiFailure(
      kind: kind,
      message: envelope.message ?? _fallbackMessage(kind),
      code: envelope.code,
      statusCode: status,
      requestId: envelope.requestId,
      cause: error,
    );
  }

  static String _fallbackMessage(ApiFailureKind kind) => switch (kind) {
        ApiFailureKind.unauthorized => '登录状态已失效，请重新登录。',
        ApiFailureKind.forbidden => '当前账号无权执行该操作。',
        ApiFailureKind.notFound => '内容不存在或已被移除。',
        ApiFailureKind.conflict => '操作与当前状态冲突，请刷新后重试。',
        ApiFailureKind.validation => '提交的内容不完整或不合法，请检查后重试。',
        ApiFailureKind.rateLimited => '操作过于频繁，请稍后再试。',
        ApiFailureKind.server => '服务器暂时不可用，请稍后重试。',
        _ => '请求失败，请稍后重试。',
      };
}

/// Parsed `{code, message, timestamp, requestId}` error envelope.
class _Envelope {
  const _Envelope({this.code, this.message, this.requestId});

  final String? code;
  final String? message;
  final String? requestId;

  static _Envelope from(Object? data) {
    if (data is! Map) {
      return const _Envelope();
    }
    return _Envelope(
      code: _asText(data['code']),
      message: _asText(data['message']),
      requestId: _asText(data['requestId']),
    );
  }

  static String? _asText(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
