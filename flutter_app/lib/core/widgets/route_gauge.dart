import 'package:flutter/material.dart';

import '../../models/travel_models.dart';
import '../data_status.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'data_status_badge.dart';

/// The itinerary drawn as a measured line.
///
/// Each stop sits on a vertical axis: time on the left, a tick on the axis,
/// content on the right. This replaces the previous stack of bordered cards so
/// that time, cost and duration line up as columns the eye can check.
///
/// [currentIndex] receives the single accent in the screen — the reader is
/// meant to see "you are here" instantly.
class RouteGauge extends StatelessWidget {
  const RouteGauge({
    super.key,
    required this.stops,
    this.currentIndex = 0,
    this.planStatus,
  });

  final List<PlanStop> stops;
  final int currentIndex;

  /// Provenance already stated for the whole plan.
  ///
  /// A stop only repeats the badge when its own status differs, otherwise the
  /// same key would appear on every node and the accent would stop meaning
  /// "you are here".
  final DataStatus? planStatus;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: List<Widget>.generate(
          stops.length,
          (index) => _GaugeRow(
            stop: stops[index],
            isFirst: index == 0,
            isLast: index == stops.length - 1,
            isCurrent: index == currentIndex,
            planStatus: planStatus,
          ),
        ),
      );
}

class _GaugeRow extends StatelessWidget {
  const _GaugeRow({
    required this.stop,
    required this.isFirst,
    required this.isLast,
    required this.isCurrent,
    required this.planStatus,
  });

  final PlanStop stop;
  final bool isFirst;
  final bool isLast;
  final bool isCurrent;
  final DataStatus? planStatus;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // IntrinsicHeight gives the axis a finite height to stretch into.
          // Without it a stretch row inside a scrolling column receives an
          // unbounded height constraint and fails to lay out.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(
                  width: AppSpacing.gaugeTimeColumn,
                  child: Text(
                    stop.time,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: AppTypography.secondary,
                      fontWeight: FontWeight.w700,
                      color: isCurrent ? AppColors.kilnRed : AppColors.ink,
                      fontFeatures: AppTypography.tabularFigures,
                      height: AppTypography.tightHeight,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.content),
                _Axis(
                  isFirst: isFirst,
                  isLast: isLast,
                  isCurrent: isCurrent,
                ),
                const SizedBox(width: AppSpacing.content),
                Expanded(
                  child: _StopDetail(stop: stop, planStatus: planStatus),
                ),
              ],
            ),
          ),
          if (!isLast) const SizedBox(height: 20),
        ],
      );
}

/// Hairline axis with a node marker. The line is suppressed above the first
/// node and below the last one, so the route reads as a finite measurement
/// rather than an infinite rail.
class _Axis extends StatelessWidget {
  const _Axis({
    required this.isFirst,
    required this.isLast,
    required this.isCurrent,
  });

  final bool isFirst;
  final bool isLast;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final Color marker = isCurrent ? AppColors.kilnRed : AppColors.celadon;
    final Widget line = Container(
      width: AppSpacing.hairline,
      color: AppColors.celadonPale,
    );

    return SizedBox(
      width: AppSpacing.tickLength,
      child: Stack(
        alignment: Alignment.topCenter,
        children: <Widget>[
          if (isLast)
            Positioned(top: isFirst ? 4 : 0, height: 4, child: line)
          else
            Positioned(top: isFirst ? 4 : 0, bottom: 0, child: line),
          Positioned(
            top: 0,
            child: Container(
              width: isCurrent ? 9 : 7,
              height: isCurrent ? 9 : 7,
              decoration: BoxDecoration(
                color: isCurrent ? AppColors.kilnRed : AppColors.ground,
                shape: BoxShape.circle,
                border: Border.all(color: marker, width: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StopDetail extends StatelessWidget {
  const _StopDetail({required this.stop, required this.planStatus});

  final PlanStop stop;
  final DataStatus? planStatus;

  @override
  Widget build(BuildContext context) {
    // The plan already states its provenance. Only repeat it per stop when this
    // stop actually differs, so the accent key stays rare and meaningful.
    final planTone = planStatus;
    final showStatus = planTone == null || stop.dataStatus != planTone;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Text(
                stop.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: AppTypography.cardTitle,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                  height: AppTypography.headingHeight,
                ),
              ),
            ),
            if (stop.cost > 0) ...<Widget>[
              const SizedBox(width: 10),
              Text(
                '¥${stop.cost}',
                style: const TextStyle(
                  fontSize: AppTypography.secondary,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                  fontFeatures: AppTypography.tabularFigures,
                ),
              ),
            ],
          ],
        ),
        if (stop.detail.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            stop.detail,
            style: const TextStyle(
              fontSize: AppTypography.caption,
              color: AppColors.crackle,
              height: 1.5,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            if ((stop.transport ?? '').isNotEmpty)
              _Unit(
                icon: Icons.directions_walk,
                text: stop.transport!,
              ),
            if ((stop.duration ?? '').isNotEmpty)
              _Unit(icon: Icons.schedule, text: stop.duration!),
            _Unit(icon: Icons.description_outlined, text: '来源 ${stop.source}'),
          ],
        ),
        if (showStatus) ...<Widget>[
          const SizedBox(height: 8),
          DataStatusBadge(status: stop.dataStatus, dense: true),
        ],
        if ((stop.risk ?? '').isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            stop.risk!,
            style: const TextStyle(
              fontSize: AppTypography.caption,
              color: AppColors.riskText,
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }
}

/// Icon plus value. Replaces the old middle-dot meta strings with labelled
/// units so each fact can be checked on its own.
class _Unit extends StatelessWidget {
  const _Unit({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 13, color: AppColors.crackle),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              fontSize: AppTypography.caption,
              color: AppColors.crackle,
            ),
          ),
        ],
      );
}
