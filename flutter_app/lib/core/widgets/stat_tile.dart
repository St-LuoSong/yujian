import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// One measurement inside the plan summary.
///
/// Value and unit sit on one baseline with tabular figures, so the row of
/// tiles reads as a column of numbers rather than a row of slogans.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.caption,
    this.tone = StatTone.plain,
    this.icon,
  });

  final String label;
  final String value;
  final String? unit;
  final String? caption;
  final StatTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final Color foreground =
        tone == StatTone.brand ? AppColors.onInk : AppColors.ink;
    final Color muted = tone == StatTone.brand
        ? AppColors.onInkMuted
        : AppColors.crackle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 13, color: muted),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppTypography.caption,
                  fontWeight: FontWeight.w600,
                  color: muted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppTypography.metricValue,
                  fontWeight: FontWeight.w700,
                  color: foreground,
                  height: AppTypography.tightHeight,
                  fontFeatures: AppTypography.tabularFigures,
                ),
              ),
            ),
            if (unit != null) ...<Widget>[
              const SizedBox(width: 2),
              Text(
                unit!,
                style: TextStyle(
                  fontSize: AppTypography.caption,
                  fontWeight: FontWeight.w600,
                  color: muted,
                ),
              ),
            ],
          ],
        ),
        if (caption != null) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            caption!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppTypography.caption,
              color: muted,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

enum StatTone { plain, brand }
