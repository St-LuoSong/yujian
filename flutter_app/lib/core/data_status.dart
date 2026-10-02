/// Cross-layer data status contract.
///
/// The value is part of the API contract shared by the Spring Boot backend,
/// the Flutter client and the admin console. The backend currently sends
/// localized labels, so [DataStatus.fromServer] normalizes them instead of
/// letting widgets compare raw Chinese strings.
enum DataStatus {
  /// Live value fetched from an external service on this request.
  realtime('实时数据'),

  /// Value served from a cache entry that is still within its TTL.
  cached('缓存数据'),

  /// Curated content shipped by the project itself (attraction library).
  system('系统资料'),

  /// Deterministic mock data used to keep the demo stable.
  mock('演示数据'),

  /// Simulated value that exists only because something upstream failed: an
  /// external data source, or the planning engine itself. The concrete reason
  /// lives in the tool trace, so the chip stays short.
  degraded('演示数据（降级）'),

  /// Produced by the language model without an external verification step.
  aiGenerated('AI 生成'),

  /// Cache entry past its expiry time.
  expired('数据已过期'),

  /// The upstream service did not return a usable value.
  unavailable('数据暂不可用'),

  /// The backend sent a status this client does not know yet.
  unknown('状态未知');

  const DataStatus(this.label);

  /// Chinese label shown to users. Keep it short enough for a chip.
  final String label;

  /// Whether the value must never be presented as verified real-time data.
  bool get isSimulated => this == mock || this == degraded;

  /// Whether the value may be shown without a re-fetch warning.
  bool get isFresh => this == realtime || this == system;

  /// Whether a re-fetch is possible and meaningful.
  bool get canRefresh =>
      this == expired || this == unavailable || this == unknown;

  static DataStatus fromServer(Object? raw) {
    if (raw is DataStatus) {
      return raw;
    }
    final text = raw?.toString().trim() ?? '';
    if (text.isEmpty) {
      return DataStatus.unknown;
    }
    if (text.contains('降级')) {
      return DataStatus.degraded;
    }
    if (text.contains('过期')) {
      return DataStatus.expired;
    }
    if (text.contains('实时')) {
      return DataStatus.realtime;
    }
    if (text.contains('缓存')) {
      return DataStatus.cached;
    }
    if (text.contains('系统资料')) {
      return DataStatus.system;
    }
    if (text.contains('演示') || text.toLowerCase().contains('mock')) {
      return DataStatus.mock;
    }
    if (text.contains('AI 生成') || text.contains('AI生成')) {
      return DataStatus.aiGenerated;
    }
    if (text.contains('不可用') || text.contains('未知')) {
      return DataStatus.unavailable;
    }
    return DataStatus.unknown;
  }
}
