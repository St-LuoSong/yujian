import 'dart:ui' show FontFeature;

/// Type scale for v0.3.
///
/// No bundled typeface on purpose: CJK font files are heavy and the offline
/// APK must not depend on network fonts. Character comes from scale, weight and
/// alignment instead. Every measurement (time, distance, price) uses
/// [tabularFigures] so numbers line up as columns.
abstract final class AppTypography {
  /// Hero headline on the discover page.
  static const double display = 30;

  static const double pageTitle = 24;
  static const double sectionTitle = 18;
  static const double cardTitle = 16;

  /// Numerals that carry the layout, for example the headline price.
  static const double measure = 22;

  /// Numeric emphasis inside a metric row.
  static const double metricValue = 18;

  /// Lead paragraph, for example an attraction summary.
  static const double lead = 16;

  static const double body = 14;
  static const double secondary = 12;
  static const double caption = 11;

  /// Unitless line height, matching the accessibility baseline.
  static const double lineHeight = 1.5;

  /// Tighter line height for multi-line display headings.
  static const double headingHeight = 1.24;

  /// Line height for numerals standing on their own.
  static const double tightHeight = 1.1;

  /// Tracking, used only for the wordmark.
  static const double wordmarkTracking = 1.5;

  /// Letter spacing for small all-caps section labels.
  static const double labelTracking = 0.6;

  /// Tabular figures: every digit takes the same width, so times, distances
  /// and prices align in a column instead of drifting.
  static const List<FontFeature> tabularFigures = <FontFeature>[
    FontFeature.tabularFigures(),
  ];
}
