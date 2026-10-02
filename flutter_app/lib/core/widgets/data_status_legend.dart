import 'package:flutter/material.dart';

import '../data_status.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'data_status_badge.dart';

/// Where the facts behind one result came from, most verified first.
///
/// Reuses the keyed-square motif of [DataStatusBadge] so a reader can connect a
/// count here with the badge on the matching row below, instead of having to
/// trust a single averaged "data quality" number.
///
/// [counts] keeps the order the caller built, because a legend that re-sorts
/// itself between two plans is unreadable.
class DataStatusLegend extends StatelessWidget {
  const DataStatusLegend({
    super.key,
    required this.counts,
    this.total,
    this.caption,
  });

  /// Non-zero count per status.
  final Map<DataStatus, int> counts;

  /// Total number of facts, shown in the caption when the caller knows it.
  final int? total;

  /// Overrides the generated caption.
  final String? caption;

  @override
  Widget build(BuildContext context) {
    if (counts.isEmpty) {
      return const SizedBox.shrink();
    }
    final String heading = caption ??
        (total == null ? '数据来源' : '数据来源共 $total 项');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          heading,
          style: const TextStyle(
            fontSize: AppTypography.caption,
            color: AppColors.crackle,
          ),
        ),
        const SizedBox(height: 8),
        // One status per line. A Row hands non-flex children unbounded width, so
        // the badge sits in an Expanded and the count stays right aligned;
        // long labels ellipsize instead of overflowing.
        for (final MapEntry<DataStatus, int> entry in counts.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: DataStatusBadge(status: entry.key, dense: true),
                ),
                const SizedBox(width: 10),
                Text(
                  '${entry.value}',
                  style: const TextStyle(
                    fontSize: AppTypography.caption,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                    fontFeatures: AppTypography.tabularFigures,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

