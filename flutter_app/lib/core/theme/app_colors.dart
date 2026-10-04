import 'package:flutter/material.dart';

/// v0.4 palette: 现代中原文化 × 淡彩山河 × 轻量旅行工具。
///
/// v0.3 已经用汝瓷天青替代了模板奶油色，但仍然偏灰：页面底色像一张纸，
/// 卡片和纸面之间只靠一条发丝线分隔。v0.4 把底色换成淡青白（雾白），
/// 把品牌青做深做稳，让山河照片有更干净的落点；麦穗金从"价格色"收回成
/// 装饰色，价格改用对比度足够的深金 [amberInk]，小字号也不会糊在白色上。
///
/// 名称保持 v0.3 的语义（ground/ink/celadon/...），只换数值：调用点遍布
/// 全工程，改名会带来一次没有收益的大面积回归。
abstract final class AppColors {
  /// 页面雾白 — page ground. 淡青白，让白色内容面板自然浮起来。
  static const Color ground = Color(0xFFF4F8F6);

  /// 匣钵 — primary text and the single dark surface.
  static const Color ink = Color(0xFF16211F);

  /// 墨淡 — body copy on a light surface when pure ink is too loud.
  static const Color inkSoft = Color(0xFF3C4A46);

  /// 品牌深青 — brand and structure colour.
  static const Color celadon = Color(0xFF145D55);

  /// 品牌青黛 — the filled brand surface (hero, primary action).
  static const Color celadonDeep = Color(0xFF1C4B46);

  /// 汝瓷浅青 — rules, ticks, tinted blocks, inactive states.
  static const Color celadonPale = Color(0xFFE4F2EE);

  /// 开片灰 — secondary text and units.
  static const Color crackle = Color(0xFF73817C);

  /// 窑变朱 — risk, and the current/next stop. Still rare on purpose.
  static const Color kilnRed = Color(0xFFC94D36);

  /// 麦穗金 — 收藏星标、餐食节点等装饰性金色。不要用小字号正文。
  static const Color amber = Color(0xFFE8B45B);

  /// 麦穗金·深 — 价格等需要读清楚的小字号金色文字。
  ///
  /// 麦穗金本身在白色上的对比度不足 2:1，直接拿去写"¥120 起"会看不清；
  /// 这里保留金色色相、把明度压到可读区间。
  static const Color amberInk = Color(0xFF8C6A1F);

  /// 陶土面 — warm tint used behind prices and season chips.
  static const Color sandSurface = Color(0xFFFBF3E3);

  /// Cards and sheets.
  static const Color surface = Color(0xFFFFFFFF);

  /// Cool tinted surface for informational blocks.
  static const Color surfaceTint = Color(0xFFEDF5F2);

  /// Slightly darker tint, for pressed or nested blocks.
  static const Color surfaceSunken = Color(0xFFDEEBE6);

  /// Risk note block.
  static const Color riskSurface = Color(0xFFFBE9E4);
  static const Color riskText = Color(0xFF8A3120);

  /// Advisory (not blocking) note block.
  static const Color cautionSurface = Color(0xFFFBF2DE);
  static const Color cautionText = Color(0xFF7A5A1C);

  /// Text on the dark surface.
  static const Color onInk = Color(0xFFF2F5F2);

  /// Muted text on the dark surface.
  static const Color onInkMuted = Color(0xFFA9BFB9);

  /// Confirmed / completed step.
  static const Color settled = Color(0xFF3F7A57);

  /// Hairline. Only for real separators, never as the main way to group.
  static const Color hairline = Color(0xFFDFE8E4);

  /// Soft drop shadow under a raised card. Low alpha, large blur: depth without
  /// a visible grey outline.
  static const List<BoxShadow> cardShadow = <BoxShadow>[
    BoxShadow(
      color: Color(0x14101D19),
      blurRadius: 18,
      offset: Offset(0, 6),
    ),
  ];

  /// Lighter shadow for chips and small raised controls.
  static const List<BoxShadow> chipShadow = <BoxShadow>[
    BoxShadow(
      color: Color(0x0F101D19),
      blurRadius: 10,
      offset: Offset(0, 3),
    ),
  ];
}
