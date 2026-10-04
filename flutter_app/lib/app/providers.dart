import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/network/api_client.dart';
import '../core/network/dio_factory.dart';
import '../core/network/session_interceptor.dart';
import '../core/platform/app_release_platform.dart';
import '../core/storage/local_cache.dart';
import '../core/storage/server_endpoint_store.dart';
import '../core/storage/session_store.dart';
import '../data/repositories/account_repository.dart';
import '../data/repositories/community_repository.dart';
import '../data/repositories/app_update_repository.dart';
import '../data/repositories/travel_repository.dart';
import 'bootstrap.dart';

/// Overridden in `main()` once the platform services are ready.
final appBootstrapProvider = Provider<AppBootstrap>(
  (ref) =>
      throw StateError('appBootstrapProvider must be overridden in main()'),
);

final serverEndpointStoreProvider = Provider<ServerEndpointStore>(
  (ref) => ref.watch(appBootstrapProvider).serverEndpointStore ??
      ServerEndpointStore(),
);

/// Runtime-editable endpoint.
///
/// `main()` seeds the first value from secure storage. Saving a new address
/// updates this notifier, which invalidates the Dio/repository providers and
/// lets the current process switch backends without a reinstall or restart.
class AppConfigController extends Notifier<AppConfig> {
  @override
  AppConfig build() => ref.watch(appBootstrapProvider).config;

  Future<void> updateEndpoint(String value) async {
    final AppConfig next = state.withEndpoint(value);
    await ref.read(serverEndpointStoreProvider).write(next.apiBaseUrl);
    state = next;
  }

  Future<void> resetEndpoint() async {
    await ref.read(serverEndpointStoreProvider).clear();
    state = AppConfig.resolve();
  }
}

final appConfigProvider =
    NotifierProvider<AppConfigController, AppConfig>(AppConfigController.new);

final sessionStoreProvider = Provider<SessionStore>(
  (ref) => ref.watch(appBootstrapProvider).sessionStore,
);

final localCacheProvider = Provider<LocalCache?>(
  (ref) => ref.watch(appBootstrapProvider).localCache,
);

final cacheSizeProvider = FutureProvider<int>(
  (ref) async => await ref.watch(localCacheProvider)?.sizeBytes() ?? 0,
);

final apiClientProvider = Provider<ApiClient>((ref) {
  final config = ref.watch(appConfigProvider);
  final sessionInterceptor = SessionInterceptor(
    store: ref.watch(sessionStoreProvider),
    refreshClient: buildBareDio(config),
    refreshPath: refreshPath,
  );
  return ApiClient(
      buildApiDio(config: config, sessionInterceptor: sessionInterceptor));
});

final travelRepositoryProvider = Provider<TravelRepository>(
  (ref) => TravelRepository(
    client: ref.watch(apiClientProvider),
    config: ref.watch(appConfigProvider),
    cache: ref.watch(localCacheProvider),
  ),
);

/// Carries a sentence typed on the discover page into the planner, so the home
/// field is a real entrance instead of a second, disconnected input.
///
/// The planner resets it to null once consumed.
final pendingPromptProvider = StateProvider<String?>((ref) => null);

/// Account bound calls: sign in, the anonymous handover, favourites.
final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => AccountRepository(
    client: ref.watch(apiClientProvider),
    session: ref.watch(sessionStoreProvider),
  ),
);

final communityRepositoryProvider = Provider<CommunityRepository>(
  (ref) => CommunityRepository(
    client: ref.watch(apiClientProvider),
    config: ref.watch(appConfigProvider),
  ),
);

final appReleasePlatformProvider = Provider<AppReleasePlatform>(
  (ref) => const AndroidAppReleasePlatform(),
);

final appUpdateRepositoryProvider = Provider<AppUpdateRepository>(
  (ref) => AppUpdateRepository(
    client: ref.watch(apiClientProvider),
    config: ref.watch(appConfigProvider),
    platform: ref.watch(appReleasePlatformProvider),
  ),
);
