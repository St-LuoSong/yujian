import '../core/data_status.dart';

/// Presentation model for a discoverable attraction.
class Destination {
  const Destination({
    required this.id,
    required this.name,
    required this.city,
    required this.theme,
    required this.image,
    required this.summary,
    required this.ticket,
    required this.duration,
    required this.audience,
    required this.weatherTip,
    this.imageCredit = '',
    this.sourceUrl = '',
    this.imageStatus = '',
    this.dataStatus = DataStatus.mock,
    this.openingHours = '',
    this.reservationNote = '',
    this.gallery = const <String>[],
    this.favoriteCount = 0,
  });

  /// [favoriteCount] 只有收藏榜接口会给出；其余接口不统计收藏数，保持 0。
  factory Destination.fromJson(
    Map<String, dynamic> json, {
    int favoriteCount = 0,
  }) =>
      Destination(
        id: _text(json['id']),
        name: _text(json['name']),
        city: _text(json['city']),
        theme: _text(json['category']),
        image: _text(json['imageUrl']),
        summary: _text(json['description']),
        ticket: _integer(json['ticketFrom']),
        duration: _text(json['duration']),
        audience: _text(json['suitability']),
        weatherTip: _text(json['weatherTip']),
        imageCredit: _text(json['imageCredit']),
        sourceUrl: _text(json['sourceUrl']),
        imageStatus: _text(json['imageStatus']),
        dataStatus: DataStatus.fromServer(json['dataStatus']),
        openingHours: _text(json['openingHours']),
        reservationNote: _text(json['reservationNote']),
        gallery: _textList(json['gallery']),
        favoriteCount: favoriteCount,
      );

  /// 收藏榜的一行：`{"poi": {...}, "favoriteCount": 3}`。
  ///
  /// 后端把计数包在景点对象外面，是为了让 /pois 那种"没统计过收藏数"的响应
  /// 不至于看起来像"零收藏"。这里兼容没有包裹的写法，旧后端也能读出景点。
  factory Destination.fromRankedJson(Map<String, dynamic> json) {
    final Object? poi = json['poi'];
    return Destination.fromJson(
      poi is Map ? poi.cast<String, dynamic>() : json,
      favoriteCount: _integer(json['favoriteCount']),
    );
  }

  final String id,
      name,
      city,
      theme,
      image,
      summary,
      duration,
      audience,
      weatherTip;

  /// 图片出处与资料链接，来自运营台。空串表示后台还没登记 —— 详情页会
  /// 直接不显示这一节，而不是编一个来源出来。
  final String imageCredit,
      sourceUrl;

  /// 配图合规状态，取值与后端 PoiImageAudit 一一对应。
  ///
  /// 空串表示服务端还没给出这个字段（旧版本），此时不额外提示，
  /// 只按 imageCredit / sourceUrl 决定要不要展示"图片来源"。
  static const String statusMissing = 'MISSING';
  static const String statusPlaceholder = 'PLACEHOLDER';
  static const String statusUnlicensed = 'UNLICENSED';
  static const String statusRegistered = 'REGISTERED';

  final String imageStatus;

  /// 配图状态对应的一句话说明。
  ///
  /// 已登记授权的实景图返回空串 —— 正常的实景照片不需要在页面上贴标签。
  /// 其余情况一律说清楚，不让游客把占位示例图当成河南实拍。
  String get imageNotice {
    switch (imageStatus) {
      case Destination.statusPlaceholder:
        return '当前为占位示例图，非河南实景，正式内容正在补充。';
      case Destination.statusMissing:
        return '该景点暂未配图。';
      case Destination.statusUnlicensed:
        return '图片版权与来源待运营台登记。';
    }
    return '';
  }

  /// 图片来源这一节要不要出现。
  ///
  /// 有说明就展示；没有说明但配图本身有问题（占位 / 缺图 / 来源未登记）时也要
  /// 展示，否则"这张图还没配好"这件事在游客端就完全看不见了。
  bool get showsImageSourceSection =>
      imageNotice.isNotEmpty ||
      imageCredit.isNotEmpty ||
      sourceUrl.isNotEmpty;

  final int ticket;
  final DataStatus dataStatus;

  /// 被收藏的次数。
  ///
  /// 0 表示"没有统计过"，不是"没人收藏"：只有收藏榜接口会带上这个数，
  /// 所以除了榜单之外的地方都不显示它。
  final int favoriteCount;

  /// 开放时间。空串表示运营台还没登记 —— 详情页显示"请以景区公告为准"，
  /// 不编造一个看起来具体的时段。
  final String openingHours;

  /// 预约说明。空串表示没有需要提醒的预约要求。
  final String reservationNote;

  /// 详情页图集（不含封面）。为空时详情页的"图集"标签页不出现。
  final List<String> gallery;
}

/// Editorial themed corridor shown on the discover page.
class TravelCorridor {
  const TravelCorridor(this.title, this.subtitle, this.duration, this.budget,
      this.image, this.tags);

  factory TravelCorridor.fromJson(Map<String, dynamic> json) => TravelCorridor(
        _text(json['title']),
        _text(json['subtitle']),
        _text(json['duration']),
        _text(json['budget']),
        _text(json['imageUrl']),
        _textList(json['highlights']),
      );

  final String title, subtitle, duration, budget, image;
  final List<String> tags;
}

/// 运营台维护的主题路线。
///
/// 与 TravelCorridor 的区别：这里多了规划提示词与图片出处，点一条路线时能
/// 直接把一句完整的自然语言带去规划页，而不是让客户端自己拼一句话。
class ThemeRoute {
  const ThemeRoute({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.cities,
    required this.duration,
    required this.budget,
    required this.coverUrl,
    required this.highlights,
    required this.planningPrompt,
    required this.imageCredit,
    required this.sourceUrl,
  });

  factory ThemeRoute.fromJson(Map<String, dynamic> json) => ThemeRoute(
        id: _text(json['id']),
        title: _text(json['title']),
        subtitle: _text(json['subtitle']),
        cities: _text(json['cities']),
        duration: _text(json['duration']),
        budget: _text(json['budget']),
        coverUrl: _text(json['coverUrl']),
        highlights: _textList(json['highlights']),
        planningPrompt: _text(json['planningPrompt']),
        imageCredit: _text(json['imageCredit']),
        sourceUrl: _text(json['sourceUrl']),
      );

  final String id, title, subtitle, cities, duration, budget, coverUrl;
  final String planningPrompt, imageCredit, sourceUrl;
  final List<String> highlights;

  /// 点这条路线时带去规划页的句子；没配时退回由标题与时长拼出的一句。
  String get prompt {
    if (planningPrompt.trim().isNotEmpty) {
      return planningPrompt.trim();
    }
    return '想把$title这条线走一遍，$duration，预算$budget，帮我安排行程。';
  }
}

/// 文化锦囊列表项（不含正文）。
class CultureArticleSummary {
  const CultureArticleSummary({
    required this.id,
    required this.title,
    required this.summary,
    required this.category,
    required this.coverUrl,
    required this.imageCredit,
    required this.sourceUrl,
    this.readingMinutes = 1,
    this.author = '',
    this.likeCount = 0,
  });

  factory CultureArticleSummary.fromJson(Map<String, dynamic> json) {
    // 老服务端没有这个字段，缺省按 1 分钟算，而不是显示"阅读 0 分钟"。
    final int minutes = _integer(json['readingMinutes']);
    return CultureArticleSummary(
        id: _text(json['id']),
        title: _text(json['title']),
        summary: _text(json['summary']),
        category: _text(json['category']),
        coverUrl: _text(json['coverUrl']),
        imageCredit: _text(json['imageCredit']),
        sourceUrl: _text(json['sourceUrl']),
        readingMinutes: minutes < 1 ? 1 : minutes,
        author: _text(json['author']),
        likeCount: _integer(json['likeCount']),
      );
  }

  final String id, title, summary, category, coverUrl, imageCredit, sourceUrl;

  /// 阅读时长（分钟），由服务端按正文字数估算。
  final int readingMinutes;

  /// 署名。为空表示运营台还没填，界面就不显示这一项。
  final String author;

  /// 展示用点赞数（运营台维护，见后端 V7 注释）。
  final int likeCount;
}

/// 文化锦囊详情（含正文）。
class CultureArticle {
  const CultureArticle({
    required this.id,
    required this.title,
    required this.summary,
    required this.content,
    required this.category,
    required this.coverUrl,
    required this.imageCredit,
    required this.sourceUrl,
    this.author = '',
    this.likeCount = 0,
  });

  factory CultureArticle.fromJson(Map<String, dynamic> json) => CultureArticle(
        id: _text(json['id']),
        title: _text(json['title']),
        summary: _text(json['summary']),
        content: _text(json['content']),
        category: _text(json['category']),
        coverUrl: _text(json['coverUrl']),
        imageCredit: _text(json['imageCredit']),
        sourceUrl: _text(json['sourceUrl']),
        author: _text(json['author']),
        likeCount: _integer(json['likeCount']),
      );

  final String id, title, summary, content, category, coverUrl;
  final String imageCredit, sourceUrl;
  final String author;
  final int likeCount;
}

/// A single stop on the itinerary timeline.
class PlanStop {
  const PlanStop(
    this.time,
    this.title,
    this.kind,
    this.detail,
    this.cost, {
    // `source` names where the value came from; `dataStatus` says how fresh it
    // is. Defaulting source to a status made every row read "演示数据 演示数据".
    this.source = '系统景点库',
    this.dataStatus = DataStatus.mock,
    this.duration,
    this.transport,
    this.risk,
  });

  factory PlanStop.fromJson(Map<String, dynamic> json) => PlanStop(
        _text(json['time']),
        _text(json['title']),
        _text(json['type']),
        _text(json['description']),
        _integer(json['cost']),
        source: _textOr(json['source'], '系统景点库'),
        dataStatus: DataStatus.fromServer(json['dataStatus']),
        duration: json['duration']?.toString(),
        transport: json['transport']?.toString(),
        risk: json['risk']?.toString(),
      );

  final String time, title, kind, detail, source;
  final int cost;
  final DataStatus dataStatus;
  final String? duration;
  final String? transport;

  /// Per stop risk note produced by the validator, for example
  /// "周一通常闭馆，请以官方公告为准".
  final String? risk;
}

/// Canonical stop categories.
///
/// Shared by the timeline (row label and rail icon) and the budget card (cost
/// split). The server hands back whatever the model wrote in `type`, which in
/// practice is a mix of Chinese ("景点") and English ("attraction",
/// "transport"). Both widgets used to compare that raw string against Chinese
/// literals, so English types fell through: the row showed "attraction" and
/// every amount landed in 其他. Classification therefore lives here once.
enum StopCategory {
  transport('交通'),
  attraction('景点'),
  meal('餐饮'),
  hotel('住宿'),
  activity('活动'),
  other('其他');

  const StopCategory(this.label);

  /// Chinese label, safe to render directly.
  final String label;

  /// Classifies a stop, preferring the structured type over the title.
  ///
  /// The type wins when it is a value we recognise. When it is missing or one
  /// we have never seen, the title still carries enough signal
  /// ("郑州至洛阳铁路出行", "老洛阳面馆") to keep the amount out of 其他.
  static StopCategory of(PlanStop stop) {
    final StopCategory typed = byText(stop.kind);
    return typed == StopCategory.other ? byText(stop.title) : typed;
  }

  /// Keyword classification. Public so it can be unit tested without a widget.
  static StopCategory byText(String? raw) {
    final String text = (raw ?? '').toLowerCase();
    if (text.isEmpty) {
      return StopCategory.other;
    }
    if (_matches(text, _transportWords)) return StopCategory.transport;
    if (_matches(text, _mealWords)) return StopCategory.meal;
    if (_matches(text, _hotelWords)) return StopCategory.hotel;
    if (_matches(text, _attractionWords)) return StopCategory.attraction;
    if (_matches(text, _activityWords)) return StopCategory.activity;
    return StopCategory.other;
  }

  static bool _matches(String text, List<String> words) =>
      words.any(text.contains);

  // 交通排在第一位：`type` 为 transport 时不会被标题里的"博物馆"之类抢走。
  static const List<String> _transportWords = <String>[
    'transport', 'traffic', 'transfer', 'transit', '交通', '铁路', '车次', '高铁',
    '动车', '火车', '驾车', '打车', '自驾', '地铁', '公交', '航班', '机场',
    '车站', '换乘', '返程',
    // 裸"站"要单独列：模型写的是"郑州东站"，它并不包含子串"车站"。
    '站',
  ];
  static const List<String> _mealWords = <String>[
    'meal', 'food', 'dining', 'restaurant', '餐饮', '餐', '小吃', '美食', '面馆',
    '餐厅', '饭店', '早餐', '午餐', '晚餐', '夜市', '水席', '咖啡馆',
  ];
  static const List<String> _hotelWords = <String>[
    'hotel', 'lodging', '住宿', '酒店', '民宿', '客栈', '入住', '退房',
  ];
  static const List<String> _attractionWords = <String>[
    'attraction', 'sight', 'museum', '景点', '景区', '门票', '博物馆', '石窟',
    '寺', '公园', '古城', '遗址', '故居', '纪念馆', '文化园', '塔', '山',
  ];
  static const List<String> _activityWords = <String>[
    'activity', '活动', '演出', '夜游', '购物', '自由', '体验', '表演',
  ];
}

class PlanDay {
  const PlanDay(this.title, this.subtitle, this.stops);

  factory PlanDay.fromJson(Map<String, dynamic> json) => PlanDay(
        _textOr(json['label'], 'DAY'),
        _textOr(json['date'], '待定'),
        _mapList(json['items']).map(PlanStop.fromJson).toList(),
      );

  final String title, subtitle;
  final List<PlanStop> stops;
}

class TravelPlan {
  const TravelPlan({
    this.id,
    required this.title,
    required this.corridor,
    required this.days,
    required this.totalCost,
    this.people = 1,
    this.intensity = '适中',
    this.warnings = const <String>[],
    this.perPersonCost,
    this.status = DataStatus.mock,
    this.statusDetail,
    this.summary = '',
  });

  factory TravelPlan.fromJson(Map<String, dynamic> json) {
    final totalCost = _integer(json['totalCost']);
    final perPersonCost = _optionalInt(json['perPersonCost']);
    return TravelPlan(
      id: _textOr(json['id'], ''),
      title: _textOr(json['title'], '河南旅行方案'),
      corridor: _textOr(json['corridor'], '河南'),
      days: _mapList(json['days']).map(PlanDay.fromJson).toList(),
      totalCost: totalCost,
      people: _peopleFrom(totalCost, perPersonCost),
      intensity: _textOr(json['intensity'], '适中'),
      warnings: _textList(json['warnings']),
      perPersonCost: perPersonCost,
      status: DataStatus.fromServer(json['dataStatus']),
      summary: _text(json['summary']),
    );
  }

  /// Server side identifier. Null for the bundled demo plans, which are not
  /// persisted and therefore cannot be adjusted, undone or traced.
  final String? id;

  final String title, corridor;
  final DataStatus status;

  /// Optional explanation shown under the status badge, for example why the
  /// plan fell back to local demo data.
  final String? statusDetail;

  /// The server's plain language account of how the plan was assembled. Shown
  /// as 规划说明 on the journey page; empty when the response omitted it.
  final String summary;

  final List<PlanDay> days;
  final int totalCost, people;

  /// 轻松 / 适中 / 紧凑, computed by the planning engine from the item count.
  final String intensity;

  /// Risk notes produced by the validator and the tool orchestration layer.
  final List<String> warnings;

  /// Server computed per person cost.
  ///
  /// Preferred over a local division because the backend truncates while
  /// `round()` here would disagree by one currency unit.
  final int? perPersonCost;

  /// Whether the plan exists on the server and can be adjusted.
  bool get isPersisted => id != null && id!.isNotEmpty;

  int get perPerson =>
      perPersonCost ?? (totalCost / (people < 1 ? 1 : people)).round();

  int get stopCount => days.fold(0, (sum, day) => sum + day.stops.length);

  /// Returns a copy with a different provenance. Used when a cached value is
  /// replayed offline so the UI can label it as cached instead of fresh.
  TravelPlan withStatus(DataStatus status, {String? detail}) => TravelPlan(
        id: id,
        title: title,
        corridor: corridor,
        days: days,
        totalCost: totalCost,
        people: people,
        intensity: intensity,
        warnings: warnings,
        perPersonCost: perPersonCost,
        status: status,
        statusDetail: detail ?? statusDetail,
        summary: summary,
      );
}

String _text(Object? value) => value?.toString() ?? '';

String _textOr(Object? value, String fallback) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

int _integer(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _optionalInt(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.round();
  }
  return int.tryParse(value.toString());
}

/// Recovers the traveller count from the two costs the API returns, because
/// `TripPlan` does not echo the request's `travelers` field.
int _peopleFrom(int totalCost, int? perPersonCost) {
  if (perPersonCost == null || perPersonCost <= 0 || totalCost <= 0) {
    return 1;
  }
  final people = (totalCost / perPersonCost).round();
  return people < 1 ? 1 : people;
}

List<Map<String, dynamic>> _mapList(Object? value) {
  if (value is! List) {
    return const <Map<String, dynamic>>[];
  }
  return value
      .whereType<Map>()
      .map((item) => item.cast<String, dynamic>())
      .toList();
}

List<String> _textList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value.map((item) => item.toString()).toList();
}
