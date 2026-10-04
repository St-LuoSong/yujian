import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Semantic tone for a [TagPill]. Colour is never the only signal: every pill
/// also carries its own words.
enum TagTone { neutral, brand, risk, caution, settled, sand }

/// A short, fully rounded label: themes, data status, risk level.
class TagPill extends StatelessWidget {
  const TagPill(
    this.label, {
    super.key,
    this.tone = TagTone.neutral,
    this.icon,
    this.dense = false,
  });

  final String label;
  final TagTone tone;
  final IconData? icon;
  final bool dense;

  Color get _background => switch (tone) {
        TagTone.neutral => AppColors.surfaceTint,
        TagTone.brand => AppColors.celadonDeep,
        TagTone.risk => AppColors.riskSurface,
        TagTone.caution => AppColors.cautionSurface,
        TagTone.settled => const Color(0xFFE4F0E8),
        TagTone.sand => AppColors.sandSurface,
      };

  Color get _foreground => switch (tone) {
        TagTone.neutral => AppColors.inkSoft,
        TagTone.brand => AppColors.onInk,
        TagTone.risk => AppColors.riskText,
        TagTone.caution => AppColors.cautionText,
        TagTone.settled => AppColors.settled,
        TagTone.sand => const Color(0xFF7A5A1C),
      };

  @override
  Widget build(BuildContext context) {
    final double fontSize = dense ? 10 : AppTypography.caption;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: _background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: fontSize + 2, color: _foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                color: _foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
