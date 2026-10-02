import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Section heading used between grouped surfaces.
///
/// v0.2 used a hairline rule with a label sitting on it. That is a magazine
/// device; here the heading is simply a title with an optional action, which
/// keeps one visual language across the discover and journey pages.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 18, color: AppColors.celadon),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: AppTypography.sectionTitle,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                    height: AppTypography.headingHeight,
                  ),
                ),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: AppTypography.caption,
                      color: AppColors.crackle,
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: AppSpacing.small),
            trailing!,
          ],
        ],
      );
}
