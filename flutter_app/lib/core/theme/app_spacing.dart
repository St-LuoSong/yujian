/// Layout tokens for v0.3.
///
/// The v0.2 scale was built around hairlines and a single 2dp radius, which is
/// why every block looked like a wireframe. v0.3 groups content into soft
/// surfaces, so the scale now carries three radii (card / control / pill) and a
/// slightly looser vertical rhythm.
///
/// Phone widths follow `docs/MOBILE_LAYOUT_SPEC.md`.
abstract final class AppSpacing {
  /// Horizontal page padding on a standard (>= 375dp) phone.
  static const double page = 20;

  /// Horizontal page padding on a compact (< 375dp) phone.
  static const double pageCompact = 16;

  /// Vertical gap between two page sections.
  static const double section = 26;

  /// Gap between related elements inside a section.
  static const double content = 12;

  /// Small gap between tightly related elements.
  static const double small = 8;

  /// Hairline width, for real separators only.
  static const double hairline = 1;

  /// Radius for grouped surfaces: attraction cards, day cards, form sections.
  static const double radiusCard = 18;

  /// Radius for inputs, buttons and small raised controls.
  static const double radiusControl = 14;

  /// Radius for nested blocks inside a card.
  static const double radiusSmall = 10;

  /// Fully rounded, for tags and dense status pills.
  static const double radiusPill = 999;

  /// Legacy alias kept so older widgets keep one shared default.
  static const double radius = radiusControl;

  /// Primary action height.
  static const double buttonHeight = 50;

  /// Minimum touch target, including icon-only buttons.
  static const double minTouchTarget = 48;

  /// Padding inside a grouped surface.
  static const double cardPadding = 16;

  /// Width of the time column in the route gauge.
  static const double gaugeTimeColumn = 52;

  /// Length of a gauge tick mark.
  static const double tickLength = 9;

  /// Below this width the layout switches to the compact padding scale.
  static const double compactBreakpoint = 375;

  /// Above this width the layout keeps a single column but gains whitespace.
  static const double wideBreakpoint = 412;

  /// Maximum readable width for body copy on wide phones.
  static const double maxContentWidth = 520;

  /// Hero height. Fixed so the first screen never jumps while the photo loads.
  static const double heroHeight = 258;

  /// Height of an attraction photo inside a card.
  static const double photoHeight = 132;

  /// Resolves the horizontal page padding for the current viewport width.
  static double pageFor(double viewportWidth) =>
      viewportWidth < compactBreakpoint ? pageCompact : page;
}
