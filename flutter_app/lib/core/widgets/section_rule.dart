import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// A section label that opens onto a hairline.
///
/// The rule is structural rather than decorative: it marks where one measured
/// block ends and the next begins, which is what replaced the v0.1 habit of
/// wrapping every block in its own bordered card.
class SectionRule extends StatelessWidget {
  const SectionRule({super.key, required this.label, this.trailing});

  final String label;

  /// Optional widget pinned to the right end of the rule, for example a
  /// provenance badge.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final trailingWidget = trailing;
    return Row(
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            fontSize: AppTypography.secondary,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(child: Divider()),
        if (trailingWidget != null) ...<Widget>[
          const SizedBox(width: 10),
          Flexible(child: trailingWidget),
        ],
      ],
    );
  }
}
