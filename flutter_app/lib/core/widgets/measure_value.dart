import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// A number with its unit and its label.
///
/// The digits are larger than the words and use tabular figures, because the
/// numbers are what a traveller actually checks. Callers wrap this in an
/// [Expanded] when they want a row of equally weighted measures.
class MeasureValue extends StatelessWidget {
  const MeasureValue({
    super.key,
    required this.value,
    required this.label,
    this.unit,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  final String value;
  final String? unit;
  final String label;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final unitText = unit;
    return Column(
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: AppTypography.measure,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                  fontFeatures: AppTypography.tabularFigures,
                  height: AppTypography.tightHeight,
                ),
              ),
            ),
            if (unitText != null) ...<Widget>[
              const SizedBox(width: 3),
              Text(
                unitText,
                style: const TextStyle(
                  fontSize: AppTypography.caption,
                  color: AppColors.crackle,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: AppTypography.caption,
            color: AppColors.crackle,
          ),
        ),
      ],
    );
  }
}
