import '../core/config/app_config.dart';
import '../core/storage/local_cache.dart';
import '../core/storage/server_endpoint_store.dart';
import '../core/storage/session_store.dart';

/// Platform services created before the first frame.
///
/// Exposed through `appBootstrapProvider` so tests can override it without
/// touching the plugin layer.
class AppBootstrap {
  const AppBootstrap(
      {required this.config,
      required this.sessionStore,
      this.serverEndpointStore,
      this.localCache});

  final AppConfig config;
  final SessionStore sessionStore;
  /// Null in widget tests that only need a fixed endpoint. Production
  /// `AppBootstrap.create()` always provides a real store.
  final ServerEndpointStore? serverEndpointStore;

  /// Null when the platform cache directory is unavailable. Offline reading is
  /// then disabled, but the app still works against the network and the
  /// bundled demo catalog.
  final LocalCache? localCache;

  static Future<AppBootstrap> create() async {
    final serverEndpointStore = ServerEndpointStore();
    final runtimeEndpoint = await serverEndpointStore.read();
    return AppBootstrap(
      config: AppConfig.resolve(runtimeEndpoint: runtimeEndpoint),
      sessionStore: SessionStore(),
      serverEndpointStore: serverEndpointStore,
      localCache: await _openCache(),
    );
  }

  static Future<LocalCache?> _openCache() async {
    try {
      return await LocalCache.open();
    } on Object {
      return null;
    }
  }
}
