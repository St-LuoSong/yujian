import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// The one grouped surface in v0.3.
///
/// It replaces the v0.2 "hairline section" as the default unit of content:
/// white, generously rounded, one soft shadow, no border unless asked for.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.cardPadding),
    this.onTap,
    this.color,
    this.border,
    this.shadow,
    this.radius = AppSpacing.radiusCard,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? border;
  final List<BoxShadow>? shadow;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final BorderRadius borderRadius = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: borderRadius,
        border: border == null ? null : Border.all(color: border!),
        boxShadow: shadow ?? AppColors.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: onTap == null
            ? Padding(padding: padding, child: child)
            : InkWell(
                onTap: onTap,
                child: Padding(padding: padding, child: child),
              ),
      ),
    );
  }
}
