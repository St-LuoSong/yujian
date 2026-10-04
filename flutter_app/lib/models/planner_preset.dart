/// 首页"从一个场景开始"带过来的预填条件。
///
/// 场景标签如果只往备注里塞一句话，用户点进来还得自己把目的地、天数、兴趣
/// 挨个填一遍 —— 入口看着能点，功能其实只做了一半。能确定的字段在这里一起
/// 带过去，表单打开就是"已经填好、可以直接改"的状态。
///
/// 每个字段都是可空的：某个场景没提到的项就保持表单原值，不做猜测。
class PlannerPreset {
  const PlannerPreset({
    required this.label,
    required this.prompt,
    this.origin,
    this.destination,
    this.days,
    this.adults,
    this.interests = const <String>[],
    this.pace,
    this.transport,
  });

  /// 场景名，用于在表单上说明"这些条件是按哪个场景填的"。
  final String label;

  /// 自然语言那一句，仍然写进备注，让后端拿到完整意图。
  final String prompt;

  final String? origin;
  final String? destination;
  final int? days;
  final int? adults;
  final List<String> interests;
  final String? pace;
  final String? transport;
}
