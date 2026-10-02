import 'package:flutter/material.dart';

import '../data_status.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Provenance marker for a value.
///
/// Deliberately not a chip. A small keyed square plus a label reads as part of
/// the measured legend instead of becoming one more bordered card. Colour is
/// never the only signal: the label always states the status in words.
class DataStatusBadge extends StatelessWidget {
  const DataStatusBadge({
    super.key,
    required this.status,
    this.updatedAt,
    this.dense = false,
  });

  final DataStatus status;

  /// When the underlying value was produced or cached.
  final DateTime? updatedAt;

  /// Slightly smaller variant for use inside list rows.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final label = updatedAt == null
        ? status.label
        : '${status.label}（${_formatTime(updatedAt!)} 更新）';
    final key = _toneFor(status);

    return Semantics(
      label: '数据状态：$label',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: dense ? 6 : 7,
            height: dense ? 6 : 7,
            decoration: BoxDecoration(
              color: key,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize:
                    dense ? AppTypography.caption : AppTypography.secondary,
                color: AppColors.crackle,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Key colour per provenance. Only simulated data earns the accent, because
  /// that is the one status a reader must not mistake for a live value.
  static Color _toneFor(DataStatus status) => switch (status) {
        DataStatus.realtime => AppColors.settled,
        DataStatus.cached => AppColors.celadon,
        DataStatus.system => AppColors.celadon,
        DataStatus.mock || DataStatus.degraded => AppColors.kilnRed,
        DataStatus.aiGenerated => AppColors.celadon,
        DataStatus.expired => AppColors.kilnRed,
        DataStatus.unavailable || DataStatus.unknown => AppColors.crackle,
      };

  static String _formatTime(DateTime value) {
    final local = value.toLocal();
    String pad(int part) => part.toString().padLeft(2, '0');
    return '${pad(local.hour)}:${pad(local.minute)}';
  }
}
