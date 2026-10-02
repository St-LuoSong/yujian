import 'package:dio/dio.dart';

import 'api_failure.dart';

/// Thin wrapper around [Dio] that normalizes every transport error into an
/// [ApiFailure].
///
/// Repositories depend on this type instead of [Dio] so that retry semantics,
/// error copy and status mapping stay in one place.
class ApiClient {
  ApiClient(this._dio);

  final Dio _dio;

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? headers,
    CancelToken? cancelToken,
  }) =>
      _send(() => _dio.get<T>(
            path,
            queryParameters: query,
            options: _options(headers),
            cancelToken: cancelToken,
          ));

  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? query,
    Map<String, dynamic>? headers,
    CancelToken? cancelToken,
  }) =>
      _send(
        () => _dio.post<T>(
          path,
          data: data,
          queryParameters: query,
          options: _options(headers),
          cancelToken: cancelToken,
        ),
      );

  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? query,
    Map<String, dynamic>? headers,
    CancelToken? cancelToken,
  }) =>
      _send(
        () => _dio.patch<T>(
          path,
          data: data,
          queryParameters: query,
          options: _options(headers),
          cancelToken: cancelToken,
        ),
      );

  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? query,
    Map<String, dynamic>? headers,
    CancelToken? cancelToken,
  }) =>
      _send(
        () => _dio.delete<T>(
          path,
          data: data,
          queryParameters: query,
          options: _options(headers),
          cancelToken: cancelToken,
        ),
      );

  /// Explicit per request headers.
  ///
  /// Needed by `merge-anonymous`, which must carry the anonymous token even
  /// though the session interceptor would otherwise prefer the new access
  /// token. Interceptor-set headers are merged on top, not replaced.
  Options? _options(Map<String, dynamic>? headers) =>
      headers == null ? null : Options(headers: headers);

  /// Reads an endpoint that answers with a single JSON object.
  Future<Map<String, dynamic>> getJsonObject(
    String path, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? headers,
  }) async {
    final data = (await get<Map<String, dynamic>>(
      path,
      query: query,
      headers: headers,
    ))
        .data;
    if (data == null) {
      throw ApiFailure.parse(StateError('$path 返回空响应'));
    }
    return data;
  }

  /// Posts a body and reads a single JSON object back.
  Future<Map<String, dynamic>> postJsonObject(
    String path, {
    Object? body,
    Map<String, dynamic>? headers,
  }) async {
    final response = await post<Map<String, dynamic>>(
      path,
      data: body,
      headers: headers,
    );
    final data = response.data;
    if (data == null) {
      throw ApiFailure.parse(StateError('$path 返回空响应'));
    }
    return data;
  }

  /// Patches a resource and reads a single JSON object back.
  Future<Map<String, dynamic>> patchJsonObject(
    String path, {
    Object? body,
    Map<String, dynamic>? headers,
  }) async {
    final response = await patch<Map<String, dynamic>>(
      path,
      data: body,
      headers: headers,
    );
    final data = response.data;
    if (data == null) {
      throw ApiFailure.parse(StateError('$path 返回空响应'));
    }
    return data;
  }

  /// Deletes a resource and reads a single JSON object back.
  Future<Map<String, dynamic>> deleteJsonObject(
    String path, {
    Object? body,
    Map<String, dynamic>? headers,
  }) async {
    final response = await delete<Map<String, dynamic>>(
      path,
      data: body,
      headers: headers,
    );
    final data = response.data;
    if (data == null) {
      throw ApiFailure.parse(StateError('$path 返回空响应'));
    }
    return data;
  }

  /// Uploads multipart data and reads a JSON object back.
  Future<Map<String, dynamic>> postMultipartJson(
    String path, {
    required FormData data,
    Map<String, dynamic>? headers,
  }) async {
    final response = await post<Map<String, dynamic>>(
      path,
      data: data,
      headers: headers,
    );
    final payload = response.data;
    if (payload == null) {
      throw ApiFailure.parse(StateError('$path 返回空响应'));
    }
    return payload;
  }

  /// Reads an endpoint that answers with a JSON array.
  Future<List<dynamic>> getJsonList(
    String path, {
    Map<String, dynamic>? headers,
  }) async {
    final data = (await get<List<dynamic>>(path, headers: headers)).data;
    if (data == null) {
      throw ApiFailure.parse(StateError('$path 返回空响应'));
    }
    return data;
  }

  /// Sends a request whose success answer carries no body, for example a `204`.
  Future<void> sendNoContent(
    Future<Response<dynamic>> Function() request,
  ) async {
    await _send(request);
  }

  Future<Response<T>> _send<T>(Future<Response<T>> Function() request) async {
    if (_dio.options.baseUrl.isEmpty) {
      throw ApiFailure.configuration('未配置服务器地址，无法加载在线数据。');
    }
    try {
      return await request();
    } on DioException catch (error) {
      throw ApiFailure.fromDio(error);
    } on ApiFailure {
      rethrow;
    } on Object catch (error) {
      throw ApiFailure.parse(error);
    }
  }
}
