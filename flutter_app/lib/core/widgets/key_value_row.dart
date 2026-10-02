import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// A labelled fact.
///
/// Replaces the v0.1 habit of joining facts with middle dots
/// ("引擎 · 版本 · 来源"). A fixed label column means every value starts at the
/// same x position, so a reader can scan down a column of facts.
class KeyValueRow extends StatelessWidget {
  const KeyValueRow({
    super.key,
    required this.label,
    required this.value,
    this.danger = false,
  });

  final String label;
  final String value;

  /// Renders the value in the accent colour, for example an error code.
  final bool danger;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 88,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: AppTypography.caption,
                  color: AppColors.crackle,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: AppTypography.caption,
                  color: danger ? AppColors.kilnRed : AppColors.ink,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      );
}
