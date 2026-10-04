import '../../core/config/app_config.dart';
import '../../core/data_status.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_failure.dart';
import '../../core/storage/local_cache.dart';
import '../../models/account_models.dart';
import '../../models/map_models.dart';
import '../../models/travel_models.dart';
import '../../models/trip_models.dart';
import '../mock_catalog.dart';

/// Outcome of a catalog read, including where the data came from.
class CatalogResult {
  const CatalogResult({
    required this.destinations,
    required this.status,
    this.updatedAt,
    this.failure,
  });

  final List<Destination> destinations;
  final DataStatus status;
  final DateTime? updatedAt;

  /// Set when the value did not come from a healthy online read.
  final ApiFailure? failure;
}

/// One page of the attraction feed.
///
/// [hasMore] comes from the server (JPA 的 hasNext). The client deliberately
/// does not derive it from page × size vs total: that arithmetic is exactly
/// where off-by-one bugs live, and an extra round trip for an empty page is
/// worse than trusting one boolean.
class DestinationPageResult {
  const DestinationPageResult({
    required this.destinations,
    required this.page,
    required this.hasMore,
    required this.status,
    this.total = 0,
    this.updatedAt,
    this.failure,
  });

  final List<Destination> destinations;
  final int page;
  final bool hasMore;

  /// 内容库里上架景点的总数。0 表示这一路没有拿到可信的总数（例如离线降级），
  /// 界面就别显示"共 N 个"，免得把一个本地切片长度说成总量。
  final int total;

  final DataStatus status;
  final DateTime? updatedAt;

  /// Set when the page did not come from a healthy online read.
  final ApiFailure? failure;

  bool get isEmpty => destinations.isEmpty;
}

/// Outcome of a planning request.
class PlanResult {
  const PlanResult({required this.plan, this.failure});

  final TravelPlan plan;

  /// Set when the plan is a cached or bundled fallback rather than a fresh
  /// server response.
  final ApiFailure? failure;

  bool get isFallback => failure != null;
}

/// Outcome of a trip list read.
class TripListResult {
  const TripListResult({
    required this.items,
    required this.status,
    this.updatedAt,
    this.failure,
  });

  final List<TripSummary> items;
  final DataStatus status;
  final DateTime? updatedAt;

  /// Set when the list came from the offline cache instead of the server.
  final ApiFailure? failure;

  bool get isEmpty => items.isEmpty;
}

/// Outcome of a footprint read.
class FootprintResult {
  const FootprintResult({
    required this.footprint,
    required this.status,
    this.failure,
  });

  final TripFootprint footprint;
  final DataStatus status;

  /// Set when the numbers could not be read from the server.
  final ApiFailure? failure;
}

/// 附近景点的一条结果。
class NearbyHit {
  const NearbyHit({required this.destination, required this.distanceMeters});

  final Destination destination;

  /// 直线距离（米），由服务端在同一坐标系下算出。
  /// 它不是步行或驾车里程 —— 界面必须照这个口径措辞。
  final int distanceMeters;
}

/// 附近景点的读取结果。
///
/// 与目录读取不同，这里**没有缓存与演示两条降级路径**：
/// 「附近的景点」是一句关于此刻在哪的话，拿一份旧坐标缓存、或者拿演示数据里的
/// 坐标去回答它，都是在编。取不到就如实说取不到，让用户重试或改用城市浏览。
class NearbySearchResult {
  const NearbySearchResult({
    required this.items,
    required this.radiusMeters,
    this.skippedWithoutCoordinate = 0,
    this.updatedAt,
    this.failure,
  });

  final List<NearbyHit> items;
  final int radiusMeters;

  /// 上架了但没配坐标、因此没能参与计算的景点数。
  /// 少了它，「附近没景点」和「附近景点都没配坐标」在界面上长得一模一样。
  final int skippedWithoutCoordinate;

  final DateTime? updatedAt;
  final ApiFailure? failure;

  bool get isEmpty => items.isEmpty;
}

/// 首页聚合内容：横幅文案与图片、主题路线、精选景点、文化锦囊预览。
///
/// 服务端把这些放在一个 /home 响应里，客户端也放在一个结果对象里 ——
/// 拆成四个 Future 只会让首屏出现"图出来了、字还在转"的割裂感。
///
/// 与目录一样走 remote -> cache -> 内置兜底：缓存里没有时给出空列表，
/// 页面据此隐藏对应板块，而不是显示一块空白。
class HomeResult {
  const HomeResult({
    required this.routes,
    required this.featured,
    required this.culture,
    required this.visual,
    required this.headline,
    required this.subline,
    required this.status,
    this.updatedAt,
    this.failure,
  });

  final List<ThemeRoute> routes;
  final List<Destination> featured;
  final List<CultureArticleSummary> culture;

  /// 视觉资源槽 -> 可直接加载的图片地址。缺某个槽表示运营还没配，
  /// 页面退回内置素材，而不是显示碎图。
  final Map<String, String> visual;

  final String headline;
  final String subline;
  final DataStatus status;
  final DateTime? updatedAt;
  final ApiFailure? failure;
}

/// 文化锦囊列表读取结果。
class CultureResult {
  const CultureResult({
    required this.items,
    required this.status,
    this.updatedAt,
    this.failure,
  });

  final List<CultureArticleSummary> items;
  final DataStatus status;
  final DateTime? updatedAt;
  final ApiFailure? failure;
}

/// 单篇文章的读取结果。article 为 null 表示这次没拿到。
class CultureArticleResult {
  const CultureArticleResult({required this.article, this.failure});

  final CultureArticle? article;
  final ApiFailure? failure;
}

/// Single entry point for catalog and trip data.
///
/// Reading strategy is `remote -> offline cache -> bundled demo data`, and the
/// returned status always says which branch answered. The client never reports
/// bundled data as a live server response.
class TravelRepository {
  TravelRepository(
      {required ApiClient client, required AppConfig config, LocalCache? cache})
      : _client = client,
        _config = config,
        _cache = cache;

  static const String missingEndpointMessage = '当前安装包未配置服务器地址，已切换到本地演示内容。';

  final ApiClient _client;
  final AppConfig _config;
  final LocalCache? _cache;

  /// Reads the catalogue, optionally narrowed to one city.
  ///
  /// 城市筛选是给「附近」页的降级路径用的：定位拿不到时，用户仍然可以按城市
  /// 浏览同一份景点库。它只影响在线请求的参数；离线与演示两条分支拿到的是
  /// 整份目录，所以在本地再过一次滤 —— 没网的时候"按城市浏览"也得成立。
  Future<CatalogResult> fetchDestinations({String? city}) async {
    final String? wanted = _cleanCity(city);
    if (!_config.hasEndpoint) {
      return CatalogResult(
        destinations: _filterByCity(destinations, wanted),
        status: DataStatus.mock,
        failure: ApiFailure.configuration(missingEndpointMessage),
      );
    }
    try {
      final response = await _client.get<List<dynamic>>(
        '/pois',
        query: wanted == null ? null : <String, dynamic>{'city': wanted},
      );
      final parsed = _parseDestinations(response.data);
      // 全量目录读空是真的有问题；某个城市读空是一个合法答案 ——
      // 不该因此降级到缓存，再把别的城市的景点端上来。
      if (parsed.isEmpty && wanted == null) {
        throw ApiFailure.parse(StateError('景点列表为空'));
      }
      // 缓存只存整份目录：拿按城市筛过的片段覆盖上去，离线时就只剩一个城市了。
      if (wanted == null) {
        await _cache?.write(LocalCache.catalogKey, response.data);
      }
      return CatalogResult(
          destinations: parsed,
          status: DataStatus.system,
          updatedAt: DateTime.now());
    } on ApiFailure catch (failure) {
      final cached = await _readCachedDestinations();
      if (cached != null) {
        return CatalogResult(
          destinations: _filterByCity(cached.destinations, wanted),
          status: DataStatus.cached,
          updatedAt: cached.updatedAt,
          failure: failure,
        );
      }
      return CatalogResult(
          destinations: _filterByCity(destinations, wanted),
          status: DataStatus.mock,
          failure: failure);
    }
  }

  /// 收藏榜：被游客收藏最多的景点，默认前 10 条。
  ///
  /// 排序与补位都在服务端完成，客户端原样呈现 —— 两头各排一次，迟早会出现
  /// "页面按收藏排、缓存按别的规则排"的偏差。服务端在收藏数相同时按运营精选
  /// 补位，所以应用刚上线、收藏还很少的时候，这一页也不会是空的。
  ///
  /// 读不到时退回本机目录的前 [limit] 条，并如实标成演示数据。
  Future<CatalogResult> fetchPopularDestinations({int limit = 10}) async {
    if (!_config.hasEndpoint) {
      return CatalogResult(
        destinations: destinations.take(limit).toList(),
        status: DataStatus.mock,
        failure: ApiFailure.configuration(missingEndpointMessage),
      );
    }
    try {
      final response = await _client.get<List<dynamic>>(
        '/pois/popular',
        query: <String, dynamic>{'limit': limit},
      );
      final List<Destination> parsed = _parseRankedDestinations(response.data);
      if (parsed.isEmpty) {
        throw ApiFailure.parse(StateError('收藏榜为空'));
      }
      return CatalogResult(
        destinations: parsed,
        status: DataStatus.system,
        updatedAt: DateTime.now(),
      );
    } on ApiFailure catch (failure) {
      return CatalogResult(
        destinations: destinations.take(limit).toList(),
        status: DataStatus.mock,
        failure: failure,
      );
    }
  }

  /// 首页默认文案。服务端没给出（旧后端、离线）时用这一份。
  static const String defaultHeadline = '河南，让旅行更简单';
  static const String defaultSubline = 'AI 智能规划 · 精准推荐 · 陪伴出行';

  /// 读取首页聚合内容。
  ///
  /// 走 remote -> cache -> 空：服务端把横幅、主题路线、精选景点和文化预览
  /// 一次给齐；失败时用上一次的缓存，缓存也没有就返回空列表，页面据此
  /// 隐藏板块（旧的硬编码走廊仍在本地作为"精选路线"的最终兜底）。
  Future<HomeResult> fetchHome() async {
    if (!_config.hasEndpoint) {
      return HomeResult(
        routes: const <ThemeRoute>[],
        featured: const <Destination>[],
        culture: const <CultureArticleSummary>[],
        visual: const <String, String>{},
        headline: defaultHeadline,
        subline: defaultSubline,
        status: DataStatus.mock,
        failure: ApiFailure.configuration(missingEndpointMessage),
      );
    }
    try {
      final response = await _client.get<Map<String, dynamic>>('/home');
      final Map<String, dynamic> data = response.data ?? const <String, dynamic>{};
      await _cache?.write(LocalCache.homeKey, data);
      return _homeFrom(data, DataStatus.system, DateTime.now());
    } on ApiFailure catch (failure) {
      final CachedEntry? cached = await _cache?.read(LocalCache.homeKey);
      final Object? payload = cached?.payload;
      if (payload is Map) {
        return _homeFrom(
          payload.cast<String, dynamic>(),
          DataStatus.cached,
          cached!.updatedAt,
          failure: failure,
        );
      }
      return HomeResult(
        routes: const <ThemeRoute>[],
        featured: const <Destination>[],
        culture: const <CultureArticleSummary>[],
        visual: const <String, String>{},
        headline: defaultHeadline,
        subline: defaultSubline,
        status: DataStatus.mock,
        failure: failure,
      );
    }
  }

  HomeResult _homeFrom(
    Map<String, dynamic> data,
    DataStatus status,
    DateTime? updatedAt, {
    ApiFailure? failure,
  }) {
    final List<ThemeRoute> routes = <ThemeRoute>[];
    final Object? rawRoutes = data['themeRoutes'];
    if (rawRoutes is List) {
      for (final Object? entry in rawRoutes) {
        if (entry is Map) {
          routes.add(ThemeRoute.fromJson(entry.cast<String, dynamic>()));
        }
      }
    }
    final List<Destination> featured = _parseDestinations(data['featuredPois']);
    final List<CultureArticleSummary> culture = <CultureArticleSummary>[];
    final Object? rawCulture = data['culturePreview'];
    if (rawCulture is List) {
      for (final Object? entry in rawCulture) {
        if (entry is Map) {
          culture.add(
              CultureArticleSummary.fromJson(entry.cast<String, dynamic>()));
        }
      }
    }
    final Map<String, String> visual = <String, String>{};
    final Object? rawVisual = data['visualResources'];
    if (rawVisual is List) {
      for (final Object? entry in rawVisual) {
        if (entry is! Map) continue;
        final Map<String, dynamic> row = entry.cast<String, dynamic>();
        final String slot = row['slot']?.toString() ?? '';
        final String raw = row['imageUrl']?.toString() ?? '';
        if (slot.isEmpty || raw.isEmpty) continue;
        visual[slot] = _config.resolveMediaUrl(raw);
      }
    }
    final String headline = data['headline']?.toString().trim() ?? '';
    final String subline = data['subline']?.toString().trim() ?? '';
    return HomeResult(
      routes: routes,
      featured: featured,
      culture: culture,
      visual: visual,
      headline: headline.isEmpty ? defaultHeadline : headline,
      subline: subline.isEmpty ? defaultSubline : subline,
      status: status,
      updatedAt: updatedAt,
      failure: failure,
    );
  }

  /// 读取文化锦囊列表。离线时退回上一次取到的列表。
  Future<CultureResult> fetchCultureArticles() async {
    if (!_config.hasEndpoint) {
      return CultureResult(
        items: const <CultureArticleSummary>[],
        status: DataStatus.mock,
        failure: ApiFailure.configuration(missingEndpointMessage),
      );
    }
    try {
      final response = await _client.get<List<dynamic>>('/culture-articles');
      final Object? raw = response.data;
      final List<Object?> list = raw is List ? raw : const <Object?>[];
      await _cache?.write(LocalCache.cultureKey, list);
      return CultureResult(
        items: _parseCulture(list),
        status: DataStatus.system,
        updatedAt: DateTime.now(),
      );
    } on ApiFailure catch (failure) {
      final CachedEntry? cached = await _cache?.read(LocalCache.cultureKey);
      final Object? payload = cached?.payload;
      if (payload is List) {
        return CultureResult(
          items: _parseCulture(payload),
          status: DataStatus.cached,
          updatedAt: cached!.updatedAt,
          failure: failure,
        );
      }
      return CultureResult(
        items: const <CultureArticleSummary>[],
        status: DataStatus.mock,
        failure: failure,
      );
    }
  }

  List<CultureArticleSummary> _parseCulture(Object? raw) {
    if (raw is! List) {
      return const <CultureArticleSummary>[];
    }
    return raw
        .whereType<Map>()
        .map((Map<dynamic, dynamic> item) =>
            CultureArticleSummary.fromJson(item.cast<String, dynamic>()))
        .toList();
  }

  Future<CultureArticleResult> fetchCultureArticle(String id) async {
    if (!_config.hasEndpoint) {
      return const CultureArticleResult(article: null);
    }
    try {
      final Map<String, dynamic> data = await _getJson('/culture-articles/$id');
      return CultureArticleResult(article: CultureArticle.fromJson(data));
    } on ApiFailure catch (failure) {
      return CultureArticleResult(article: null, failure: failure);
    }
  }

  /// 首页一屏放得下的卡片数。
  static const int destinationPageSize = 6;

  /// 附近景点的默认半径与条数，与后端默认值保持一致。
  /// 后端会把越界值夹回合法区间，这里传的只是"想要多少"。
  static const int defaultNearbyRadiusMeters = 3000;
  static const int defaultNearbyLimit = 10;

  /// Reads one page of the attraction feed.
  ///
  /// The discover page shows six cards and asks for the next page as the
  /// traveller scrolls, so a long content library never turns into one big
  /// response. Pages that were already loaded are merged into the offline
  /// cache, which is why a cached read can still answer page 2 with no network.
  ///
  /// A missing endpoint or a failed request degrades to the cached list first
  /// and to the bundled demo catalogue last — and [status] always says which
  /// branch answered, so the badge on the page never claims cached data is
  /// live.
  Future<DestinationPageResult> fetchDestinationPage({
    int page = 1,
    int size = destinationPageSize,
  }) async {
    final int safePage = page < 1 ? 1 : page;
    final int safeSize = size < 1 ? destinationPageSize : size;
    if (!_config.hasEndpoint) {
      return _pagedSlice(destinations, safePage, safeSize, DataStatus.mock,
          ApiFailure.configuration(missingEndpointMessage));
    }
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/pois/page',
        query: <String, dynamic>{'page': safePage, 'size': safeSize},
      );
      final Map<String, dynamic> data = response.data ?? const <String, dynamic>{};
      final List<Destination> parsed = _parseDestinations(data['items']);
      if (parsed.isEmpty && safePage == 1) {
        throw ApiFailure.parse(StateError('景点列表为空'));
      }
      await _mergeCachedCatalog(data['items'], leading: safePage == 1);
      return DestinationPageResult(
        destinations: parsed,
        page: _pageNumber(data['page'], safePage),
        hasMore: data['hasMore'] == true,
        total: _count(data['total']),
        status: DataStatus.system,
        updatedAt: DateTime.now(),
      );
    } on ApiFailure catch (failure) {
      final cached = await _readCachedDestinations();
      final List<Destination> pool = cached?.destinations ?? destinations;
      return _pagedSlice(
        pool,
        safePage,
        safeSize,
        cached != null ? DataStatus.cached : DataStatus.mock,
        failure,
        updatedAt: cached?.updatedAt,
      );
    }
  }

  /// Creates a plan from the traveller's stated conditions.
  ///
  /// Every field except [prompt] is optional: the journey form collects them,
  /// but a one line entrance from the discover page only has the sentence.
  ///
  /// [startDate] is the traveller's departure date (`yyyy-MM-dd`): the single
  /// time basis the server accepts. Weather, trains and the date stamped on
  /// every day of the plan are derived from it. Leaving it null lets the server
  /// fall back to tomorrow, which is why the form always sends it.
  Future<PlanResult> createPlan({
    required String prompt,
    String? startDate,
    String? origin,
    String? destination,
    int people = 2,
    int days = 2,
    int? budgetPerPerson,
    String? interests,
    String? pace,
    String? transport,
  }) async {
    final fallbackDestination = destination ?? '洛阳';
    if (!_config.hasEndpoint) {
      final failure = ApiFailure.configuration(missingEndpointMessage);
      return PlanResult(
          plan: _demoPlan(fallbackDestination, people, failure),
          failure: failure);
    }
    try {
      final response = await _client.post<Map<String, dynamic>>(
        '/trip-plans',
        data: <String, Object?>{
          'prompt': prompt,
          'startDate': startDate,
          'origin': origin,
          'destination': destination,
          'travelers': people,
          'days': days,
          'budgetPerPerson': budgetPerPerson,
          'interests': interests,
          'pace': pace,
          'transport': transport,
        },
      );
      final data = response.data;
      if (data == null) {
        throw ApiFailure.parse(StateError('行程响应为空'));
      }
      final plan = TravelPlan.fromJson(data);
      await _cache?.write(LocalCache.latestPlanKey, data);
      return PlanResult(plan: plan);
    } on ApiFailure catch (failure) {
      if (failure.isTrialLimit || failure.kind == ApiFailureKind.validation) {
        // These must reach the user: answering with demo data would hide a real
        // trial limit or an invalid request.
        rethrow;
      }
      final cached = await _readCachedPlan();
      if (cached != null) {
        return PlanResult(
          plan: cached.withStatus(DataStatus.cached, detail: failure.message),
          failure: failure,
        );
      }
      return PlanResult(
          plan: _demoPlan(fallbackDestination, people, failure),
          failure: failure);
    }
  }

  TravelPlan _demoPlan(String destination, int people, ApiFailure failure) =>
      demoPlan(destination: destination, people: people)
          .withStatus(DataStatus.mock, detail: failure.message);

  /// Applies a natural language adjustment to a persisted plan.
  ///
  /// Only plans that exist on the server can be adjusted. A bundled demo plan
  /// has no id, so the caller must not offer the action; this method never
  /// fabricates a local adjustment.
  Future<AdjustmentResult> adjustTripPlan({
    required String planId,
    required String instruction,
  }) async {
    final data = await _postJson(
      '/trip-plans/$planId/adjust',
      <String, Object?>{'instruction': instruction},
    );
    return AdjustmentResult.fromJson(data);
  }

  /// Restores the snapshot taken before the last adjustment.
  Future<TravelPlan> undoTripPlan(String planId) async {
    final data = await _postJson('/trip-plans/$planId/undo', null);
    return TravelPlan.fromJson(data);
  }

  /// Returns the engine, prompt version and per-tool evidence for a plan.
  Future<TraceInfo> fetchTrace(String planId) async {
    final data = await _getJson('/trip-plans/$planId/trace');
    return TraceInfo.fromJson(data);
  }

  /// Lists the trips owned by the current session.
  ///
  /// When the server is unreachable the most recent cached plan is returned as
  /// a single entry, clearly labelled as cached, so the "行程" tab is never
  /// blank for a user who was just working on a plan.
  Future<TripListResult> fetchTripPlans() async {
    if (!_config.hasEndpoint) {
      return _tripListFallback(
          ApiFailure.configuration(missingEndpointMessage));
    }
    try {
      final raw = await _getJsonList('/trip-plans');
      final items = raw
          .whereType<Map>()
          .map((item) => TripSummary.fromJson(item.cast<String, dynamic>()))
          .toList();
      return TripListResult(
          items: items, status: DataStatus.system, updatedAt: DateTime.now());
    } on ApiFailure catch (failure) {
      return _tripListFallback(failure);
    }
  }

  /// "你的足迹"聚合。服务端按当前会话（登录账号或匿名体验）统计。
  ///
  /// 拿不到就返回空足迹：这里**不做任何本地估算**。按天数或景点数凑一个
  /// 公里数，看起来热闹，但那是编出来的数字，宁可不显示。
  Future<FootprintResult> fetchFootprint() async {
    if (!_config.hasEndpoint) {
      return FootprintResult(
        footprint: TripFootprint.empty,
        status: DataStatus.unavailable,
        failure: ApiFailure.configuration(missingEndpointMessage),
      );
    }
    try {
      final data = await _getJson('/trip-plans/footprint');
      return FootprintResult(
        footprint: TripFootprint.fromJson(data),
        status: DataStatus.system,
      );
    } on ApiFailure catch (failure) {
      return FootprintResult(
        footprint: TripFootprint.empty,
        status: DataStatus.unavailable,
        failure: failure,
      );
    }
  }

  /// Loads a full plan. The list endpoint only returns summaries.
  Future<PlanResult> fetchTripPlan(String planId) async {
    try {
      final data = await _getJson('/trip-plans/$planId');
      return PlanResult(plan: TravelPlan.fromJson(data));
    } on ApiFailure catch (failure) {
      final cached = await _readCachedPlan();
      if (cached != null && cached.id == planId) {
        return PlanResult(
          plan: cached.withStatus(DataStatus.cached, detail: failure.message),
          failure: failure,
        );
      }
      rethrow;
    }
  }

  /// Renames a saved plan.
  ///
  /// The server owns the plan (and re-checks the owner), so the caller reloads
  /// the list afterwards instead of patching a local copy and hoping the two
  /// agree. A blank title is rejected here: the backend would silently keep the
  /// old one and the user would think the rename went through.
  Future<void> renameTripPlan({
    required String planId,
    required String title,
  }) async {
    final String trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw const ApiFailure(
        kind: ApiFailureKind.validation,
        message: '行程名称不能为空。',
      );
    }
    await _client.patch<dynamic>(
      '/trip-plans/$planId',
      data: <String, Object?>{'title': trimmed},
    );
  }

  /// Deletes a saved plan. Days and items go with it (cascade on the server),
  /// and only the owner can, which the server enforces per request.
  Future<void> deleteTripPlan(String planId) async {
    await _client.sendNoContent(
      () => _client.delete<dynamic>('/trip-plans/$planId'),
    );
  }

  /// Today's next stop and remaining items.
  Future<TodayInfo> fetchToday(String planId) async {
    try {
      final data = await _getJson('/trip-plans/$planId/today');
      return TodayInfo.fromJson(data);
    } on ApiFailure {
      final cached = await _readCachedPlan();
      if (cached != null) {
        return TodayInfo.fromPlan(cached, status: DataStatus.cached);
      }
      rethrow;
    }
  }

  Future<TripListResult> _tripListFallback(ApiFailure failure) async {
    final cached = await _readCachedPlan();
    if (cached == null) {
      return TripListResult(
          items: const <TripSummary>[],
          status: DataStatus.unavailable,
          failure: failure);
    }
    return TripListResult(
      items: <TripSummary>[
        TripSummary.fromPlan(cached, status: DataStatus.cached)
      ],
      status: DataStatus.cached,
      failure: failure,
    );
  }

  /// 读取某一天的行程地图快照。
  ///
  /// 底图、投影与票据都由服务端给出，客户端只负责画：
  /// - [centerLng] / [centerLat] / [zoom] 传上一张快照的窗口，用于缩放或复位；
  /// - [panX] / [panY] 是拖动产生的"视野中心像素位移"（向右/向下为正），
  ///   由服务端换算成新的中心点，APK 不需要懂百度坐标系。
  ///
  /// 服务端在取不到底图时会返回 fallback 快照而不是报错，
  /// 因此这里只在真正连不上服务器时抛出 [ApiFailure]。
  Future<RouteMapSnapshot> fetchRouteMap({
    required String planId,
    required int day,
    double? centerLng,
    double? centerLat,
    int? zoom,
    double? panX,
    double? panY,
  }) async {
    if (!_config.hasEndpoint) {
      throw ApiFailure.configuration(missingEndpointMessage);
    }
    final Map<String, dynamic> query = <String, dynamic>{'day': day};
    if (centerLng != null && centerLat != null) {
      query['center'] = '$centerLng,$centerLat';
    }
    if (zoom != null) {
      query['zoom'] = zoom;
    }
    if (panX != null && panX != 0) {
      query['panX'] = panX;
    }
    if (panY != null && panY != 0) {
      query['panY'] = panY;
    }
    final response = await _client.get<Map<String, dynamic>>(
      '/trip-plans/$planId/map',
      query: query,
    );
    final data = response.data;
    if (data == null) {
      throw ApiFailure.parse(StateError('地图快照响应为空'));
    }
    final snapshot = RouteMapSnapshot.fromJson(data);
    if (snapshot.imageUrl.isEmpty) {
      return snapshot;
    }
    // 服务端返回的是相对路径，这里换算成这台设备真正能访问的地址。
    return RouteMapSnapshot.fromJson(
      <String, dynamic>{...data, 'imageUrl': _config.resolveMediaUrl(snapshot.imageUrl)},
    );
  }

  /// Creates a read only share link.
  ///
  /// The server requires a signed in owner and a plan that belongs to that
  /// account, so an anonymous trial must be merged before sharing works.
  Future<TripShareLink> createShareLink({
    required String planId,
    bool hideBudget = true,
    int expireDays = 7,
  }) async {
    final data = await _postJson(
      '/trip-plans/$planId/share',
      <String, Object?>{'hideBudget': hideBudget, 'expireDays': expireDays},
    );
    return TripShareLink.fromJson(data);
  }

  /// Turns a share link off so the URL stops resolving.
  Future<void> revokeShareLink(String shareId) async {
    await _client.sendNoContent(
      () => _client.delete<dynamic>('/trip-shares/$shareId'),
    );
  }

  /// 读取附近的景点。
  ///
  /// 坐标由设备定位提供，是原始 WGS-84；换成内容库使用的 BD-09 由服务端负责 ——
  /// 坐标系只该在服务端踩一次坑，而且那样换底图时不需要所有已发布的 APK 跟着升版。
  ///
  /// 这个接口**不降级**：没有缓存分支，也没有演示数据分支，失败就是失败。
  /// 理由见 [NearbySearchResult] 的注释。
  Future<NearbySearchResult> fetchNearby({
    required double lng,
    required double lat,
    int radius = defaultNearbyRadiusMeters,
    int limit = defaultNearbyLimit,
  }) async {
    if (!_config.hasEndpoint) {
      return NearbySearchResult(
        items: const <NearbyHit>[],
        radiusMeters: radius,
        failure: ApiFailure.configuration(missingEndpointMessage),
      );
    }
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/pois/nearby',
        query: <String, dynamic>{
          'lng': lng,
          'lat': lat,
          'radius': radius,
          'limit': limit,
        },
      );
      final Map<String, dynamic>? data = response.data;
      if (data == null) {
        throw ApiFailure.parse(StateError('/pois/nearby 返回空响应'));
      }

      final List<NearbyHit> items = <NearbyHit>[];
      final Object? rawItems = data['items'];
      if (rawItems is List) {
        for (final Object? entry in rawItems) {
          if (entry is! Map) {
            continue;
          }
          final Map<String, dynamic> row = entry.cast<String, dynamic>();
          final Object? poi = row['poi'];
          if (poi is! Map) {
            // 一条结构不对的记录不该让整次查询失败 —— 丢掉它，其余照常显示。
            continue;
          }
          items.add(NearbyHit(
            destination: Destination.fromJson(
              _reachablePhoto(poi.cast<String, dynamic>()),
            ),
            distanceMeters: _count(row['distanceMeters']),
          ));
        }
      }

      return NearbySearchResult(
        items: items,
        radiusMeters: _positiveOr(data['radiusMeters'], radius),
        skippedWithoutCoordinate: _count(data['skippedWithoutCoordinate']),
        updatedAt: DateTime.now(),
      );
    } on ApiFailure catch (failure) {
      return NearbySearchResult(
        items: const <NearbyHit>[],
        radiusMeters: radius,
        failure: failure,
      );
    }
  }

  Future<List<dynamic>> _getJsonList(String path) => _client.getJsonList(path);

  Future<Map<String, dynamic>> _getJson(String path) =>
      _client.getJsonObject(path);

  Future<Map<String, dynamic>> _postJson(String path, Object? body) =>
      _client.postJsonObject(path, body: body);

  /// Slices an in-memory list into the page the caller asked for.
  ///
  /// Used by both offline branches: the cached catalogue and the bundled demo
  /// data are already whole lists, and the page the traveller is on is just a
  /// window into them.
  DestinationPageResult _pagedSlice(
    List<Destination> pool,
    int page,
    int size,
    DataStatus status,
    ApiFailure failure, {
    DateTime? updatedAt,
  }) {
    final int start = (page - 1) * size;
    if (start >= pool.length) {
      return DestinationPageResult(
        destinations: const <Destination>[],
        page: page,
        hasMore: false,
        total: pool.length,
        status: status,
        updatedAt: updatedAt,
        failure: failure,
      );
    }
    final int end = start + size;
    final List<Destination> slice =
        pool.sublist(start, end > pool.length ? pool.length : end);
    return DestinationPageResult(
      destinations: slice,
      page: page,
      hasMore: end < pool.length,
      total: pool.length,
      status: status,
      updatedAt: updatedAt,
      failure: failure,
    );
  }

  /// Grows the offline catalogue with the page that just arrived.
  ///
  /// Page 1 leads (a newly published attraction is usually placed first, and the
  /// operator's ordering is not visible to the client), later pages append. The
  /// cache is keyed by id, so re-reading page 1 after pages 2-3 does not
  /// duplicate rows.
  Future<void> _mergeCachedCatalog(Object? freshRaw, {required bool leading}) async {
    final cache = _cache;
    if (cache == null || freshRaw is! List || freshRaw.isEmpty) {
      return;
    }
    final entry = await cache.read(LocalCache.catalogKey);
    final List<Object?> merged = <Object?>[];
    final Set<String> seen = <String>{};
    void drain(Object? payload) {
      if (payload is! List) {
        return;
      }
      for (final item in payload) {
        final id = item is Map ? item['id']?.toString() : null;
        if (id == null || id.isEmpty || !seen.add(id)) {
          continue;
        }
        merged.add(item);
      }
    }

    if (leading) {
      drain(freshRaw);
      drain(entry?.payload);
    } else {
      drain(entry?.payload);
      drain(freshRaw);
    }
    await cache.write(LocalCache.catalogKey, merged);
  }

  static int _count(Object? raw) {
    if (raw is int && raw > 0) {
      return raw;
    }
    final parsed = int.tryParse(raw?.toString() ?? '');
    return parsed != null && parsed > 0 ? parsed : 0;
  }

  /// 服务端回报的半径如果不是正数（旧版本、字段缺失），就用本地请求的那个值，
  /// 免得界面上出现「0 米内」这种明显是错的文案。
  static int _positiveOr(Object? raw, int fallback) {
    final parsed = _count(raw);
    return parsed > 0 ? parsed : fallback;
  }

  static int _pageNumber(Object? raw, int fallback) {
    if (raw is int && raw > 0) {
      return raw;
    }
    final parsed = int.tryParse(raw?.toString() ?? '');
    return parsed != null && parsed > 0 ? parsed : fallback;
  }

  Future<({List<Destination> destinations, DateTime updatedAt})?>
      _readCachedDestinations() async {
    final cache = _cache;
    if (cache == null) {
      return null;
    }
    final entry = await cache.read(LocalCache.catalogKey);
    if (entry == null) {
      return null;
    }
    final parsed = _parseDestinations(entry.payload);
    if (parsed.isEmpty) {
      return null;
    }
    return (destinations: parsed, updatedAt: entry.updatedAt);
  }

  Future<TravelPlan?> _readCachedPlan() async {
    final entry = await _cache?.read(LocalCache.latestPlanKey);
    final payload = entry?.payload;
    if (payload is! Map) {
      return null;
    }
    return TravelPlan.fromJson(payload.cast<String, dynamic>());
  }

  /// 空串与纯空格当作"没有指定城市"，免得界面上一个手滑的空字符串
  /// 变成一个查不到东西的请求。
  static String? _cleanCity(String? city) {
    final String trimmed = city?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  /// 按城市过滤。
  ///
  /// 用 `contains` 是与后端对齐的（后端用的是 `cityContaining`）：
  /// 卡片上写的是"洛阳"，而运营台可能把城市填成"洛阳市"，两边必须能对上。
  static List<Destination> _filterByCity(List<Destination> pool, String? city) {
    if (city == null) {
      return pool;
    }
    return pool
        .where((Destination item) => item.city.contains(city))
        .toList();
  }

  List<Destination> _parseDestinations(Object? data) {
    if (data is! List) {
      return const <Destination>[];
    }
    return data
        .whereType<Map>()
        .map((item) =>
            Destination.fromJson(_reachablePhoto(item.cast<String, dynamic>())))
        .toList();
  }

  /// 解析 `/pois/popular` 的 `{poi, favoriteCount}` 行，同时兼容旧后端的平铺写法。
  List<Destination> _parseRankedDestinations(Object? data) {
    if (data is! List) {
      return const <Destination>[];
    }
    return data.whereType<Map>().map((Map<dynamic, dynamic> item) {
      final Map<String, dynamic> row = item.cast<String, dynamic>();
      final Object? poi = row['poi'];
      if (poi is Map) {
        return Destination.fromRankedJson(<String, dynamic>{
          'poi': _reachablePhoto(poi.cast<String, dynamic>()),
          'favoriteCount': row['favoriteCount'],
        });
      }
      return Destination.fromJson(_reachablePhoto(row));
    }).toList();
  }

  /// The backend derives a photo URL from whoever uploaded it, so a picture
  /// uploaded in the operator console arrives as `http://localhost:8080/...`
  /// and would never load on the phone. Resolving it here is the single choke
  /// point every destination passes through: the discover grid, the detail
  /// header and the day covers all reuse this model.
  Map<String, dynamic> _reachablePhoto(Map<String, dynamic> json) {
    final raw = json['imageUrl'];
    if (raw is! String || raw.isEmpty) {
      return json;
    }
    final resolved = _config.resolveMediaUrl(raw);
    if (resolved == raw) {
      return json;
    }
    return <String, dynamic>{...json, 'imageUrl': resolved};
  }
}
