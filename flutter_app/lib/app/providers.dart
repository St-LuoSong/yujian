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
import '../models/planner_preset.dart';
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

/// 首页"从一个场景开始"点选后带过来的预填条件。
///
/// 和 pendingPromptProvider 分开：那句话是"用户说了什么"，
/// 这一份是"能替他先填好的字段"。两者可以只有其一 ——
/// 手输一句话进来时没有预设，点场景时两个都有。
final pendingPlannerPresetProvider = StateProvider<PlannerPreset?>((ref) => null);

/// 主导航当前所在的 Tab。
///
/// 放在 provider 而不是 HomeScreen 的局部 state：文化锦囊弹窗里的
/// "用这个主题做一份行程"要能把用户送回行程页，局部 state 做不到。
final homeTabProvider = StateProvider<int>((ref) => 0);

/// 文化锦囊的文章弹窗是否展开成整屏。
///
/// 弹窗的高度由外面那层 FractionallySizedBox 决定，而"展开"按钮在弹窗内部 ——
/// 两边都要读到同一个值，所以放在 provider 里，而不是各自的局部 state。
final cultureSheetExpandedProvider = StateProvider<bool>((ref) => false);

/// 全局视觉资源槽：首页横幅（HOME_HERO）、我的页头图（PROFILE_HEADER）、
/// 文化锦囊头图（CULTURE_HEADER）等。
///
/// 一次取、多个页面共用；服务端没配就返回空表，页面各自回落内置样式 ——
/// 运营没配图不该让任何一个页面变空白。
final visualResourcesProvider = FutureProvider<Map<String, String>>((ref) async {
  final HomeResult home =
      await ref.watch(travelRepositoryProvider).fetchHome();
  return home.visual;
});

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
