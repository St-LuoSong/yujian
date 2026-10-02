import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:yujian_travel/core/config/app_config.dart';
import 'package:yujian_travel/core/storage/session_store.dart';

/// Base URL used by every fake request in the suite.
const String testBaseUrl = 'https://api.example.test/api';

const AppConfig testConfig = AppConfig(
  apiBaseUrl: testBaseUrl,
  connectTimeout: Duration(seconds: 1),
  receiveTimeout: Duration(seconds: 1),
  sendTimeout: Duration(seconds: 1),
);

const Map<String, List<String>> jsonHeaders = <String, List<String>>{
  Headers.contentTypeHeader: <String>[Headers.jsonContentType],
};

ResponseBody jsonBody(Object value, {int status = 200}) =>
    ResponseBody.fromString(jsonEncode(value), status, headers: jsonHeaders);

/// Dio whose transport is a fake, so a repository can be driven without a
/// network and every request can be asserted afterwards.
Dio dioWith(HttpClientAdapter adapter, {String baseUrl = testBaseUrl}) =>
    Dio(BaseOptions(baseUrl: baseUrl, responseType: ResponseType.json))
      ..httpClientAdapter = adapter;

/// Records every request and delegates the reply to [handler].
class RecordingAdapter implements HttpClientAdapter {
  RecordingAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options, String? body)
      handler;

  /// Every request the repository made, in order.
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final body =
        requestStream == null ? null : await utf8.decodeStream(requestStream);
    return handler(options, body);
  }

  @override
  void close({bool force = false}) {}
}

/// In-memory keystore, so session behaviour can be tested without the plugin.
class MemoryKeyValueStore implements SecureKeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
