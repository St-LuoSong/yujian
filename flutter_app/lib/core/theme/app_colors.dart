import 'package:flutter/material.dart';

/// v0.3 palette: 汝瓷天青 · 匣钵墨 · 窑变朱，落在温暖的纸面上。
///
/// The v0.2 palette was cool and flat on purpose: it replaced a warm cream
/// template. The problem was that a flat, hairline-only page reads as a
/// wireframe, and everything ended up the same weight. v0.3 keeps the same
/// Henan materials (Ru-ware celadon, kiln red) but puts them on a surface that
/// can carry photography, with soft depth and one warm price accent.
///
/// Full rationale: `docs/DESIGN_DIRECTION.md`.
abstract final class AppColors {
  /// 纸面 — page ground. A soft neutral, deliberately not the warm cream
  /// default and not the sterile grey of a dashboard.
  static const Color ground = Color(0xFFF1F3EF);

  /// 匣钵 — primary text and the single dark surface.
  static const Color ink = Color(0xFF16211F);

  /// 墨淡 — body copy on a light surface when pure ink is too loud.
  static const Color inkSoft = Color(0xFF3B4744);

  /// 天青 — brand and structure colour, taken from 汝瓷.
  static const Color celadon = Color(0xFF2F6F68);

  /// 天青深 — the filled brand surface (hero, primary action).
  static const Color celadonDeep = Color(0xFF1C4B46);

  /// 天青淡 — rules, ticks, inactive states.
  static const Color celadonPale = Color(0xFFCFE0DB);

  /// 开片灰 — secondary text and units.
  static const Color crackle = Color(0xFF78867F);

  /// 窑变朱 — risk, and the current/next stop. Still rare on purpose.
  static const Color kilnRed = Color(0xFFB23A22);

  /// 麦穗 — the price accent. One warm colour, used only for money.
  static const Color amber = Color(0xFFB98A3C);

  /// 陶土面 — warm tint used behind prices and season chips.
  static const Color sandSurface = Color(0xFFF7F0E2);

  /// Cards and sheets.
  static const Color surface = Color(0xFFFFFFFF);

  /// Cool tinted surface for informational blocks.
  static const Color surfaceTint = Color(0xFFE8EFEC);

  /// Slightly darker tint, for pressed or nested blocks.
  static const Color surfaceSunken = Color(0xFFDDE6E2);

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
  static const Color hairline = Color(0xFFE1E6E1);

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
