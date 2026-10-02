import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// 出发地 ⇄ 目的地。
///
/// 这不是两个下拉框。中间那个环形箭头是主操作：点一下两侧的值真的互换，
/// 而且交换时有动画告诉用户「哪个值去了哪一边」——左侧的字往右滑走、
/// 右侧的字往左滑走，方向就是值移动的方向，而不是让两个地名瞬间对调。
///
/// 两侧各自可点，点了由调用方打开城市选择弹层；本组件不持有城市数据，
/// 只负责把当前值、交换动作和点击出口摆在一起。
class RouteSelector extends StatefulWidget {
  const RouteSelector({
    super.key,
    required this.origin,
    required this.destination,
    required this.onSwap,
    required this.onPickOrigin,
    required this.onPickDestination,
    this.enabled = true,
  });

  final String origin;
  final String destination;

  /// 交换两侧。由调用方改状态，本组件只负责把「换过了」演出来。
  final VoidCallback onSwap;

  final VoidCallback onPickOrigin;
  final VoidCallback onPickDestination;
  final bool enabled;

  @override
  State<RouteSelector> createState() => _RouteSelectorState();
}

class _RouteSelectorState extends State<RouteSelector>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  /// 每次点击转半圈。环形箭头转 180° 后与自身重合，所以下一次点击
  /// 从 0 重新开始也不会看到跳动。
  late final Animation<double> _turn = Tween<double>(begin: 0, end: 0.5).animate(
    CurvedAnimation(parent: _spin, curve: Curves.easeInOutCubic),
  );

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  void _swap() {
    widget.onSwap();
    // 系统开了「移除动画」时只换值，不转圈。
    final bool reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _spin.value = 0;
      return;
    }
    unawaited(_spin.forward(from: 0));
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceTint,
          borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: _CityField(
                label: '出发地',
                city: widget.origin,
                icon: Icons.trip_origin,
                alignment: Alignment.centerLeft,
                textAlign: TextAlign.left,
                slideFrom: 1,
                enabled: widget.enabled,
                onTap: widget.onPickOrigin,
              ),
            ),
            _SwapButton(
              turn: _turn,
              enabled: widget.enabled,
              onTap: _swap,
            ),
            Expanded(
              child: _CityField(
                label: '目的地',
                city: widget.destination,
                icon: Icons.place_outlined,
                alignment: Alignment.centerRight,
                textAlign: TextAlign.right,
                slideFrom: -1,
                enabled: widget.enabled,
                onTap: widget.onPickDestination,
              ),
            ),
          ],
        ),
      );
}

class _CityField extends StatelessWidget {
  const _CityField({
    required this.label,
    required this.city,
    required this.icon,
    required this.alignment,
    required this.textAlign,
    required this.slideFrom,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final String city;
  final IconData icon;
  final Alignment alignment;
  final TextAlign textAlign;

  /// 换到新值时从哪一侧滑进来，单位是控件宽度。1 = 从右，-1 = 从左。
  final double slideFrom;

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(icon, size: 12, color: AppColors.crackle),
                    const SizedBox(width: 4),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: AppTypography.caption,
                        fontWeight: FontWeight.w600,
                        color: AppColors.crackle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  height: 26,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    layoutBuilder: (
                      Widget? current,
                      List<Widget> previous,
                    ) =>
                        Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        ...previous,
                        if (current != null) current,
                      ],
                    ),
                    // 用 SlideTransition 而不是 FractionalTranslation 算位移。
                    //
                    // 这里必须用「自己监听动画」的组件：AnimatedSwitcher 只在
                    // 建树时把 animation 交给 transitionBuilder 一次，之后只会让
                    // 动画自己 tick。FractionalTranslation 收到的是一帧的数值，
                    // 新值恰好是在 animation.value == 0 那一帧建出来的，于是
                    // 「往外 1 个身位」被永久固定，文字被 ClipRect 裁掉 —— 表现
                    // 就是交换后两侧城市名一起消失，切页重建（此时 value 已是 1）
                    // 才恢复正常。SlideTransition 逐帧读取动画，进出都跟着走。
                    //
                    // 同一个 tween 同时管进和出：AnimatedSwitcher 让旧值那条动画
                    // 反向播放，所以它在 `slideFrom` 方向滑出去、新值从同侧滑进来，
                    // 看上去就是这个值整块平移了过去。
                    transitionBuilder: (
                      Widget child,
                      Animation<double> animation,
                    ) =>
                        ClipRect(
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: Offset(slideFrom, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: FadeTransition(
                          opacity: animation,
                          child: child,
                        ),
                      ),
                    ),
                    // key 必须挂在 AnimatedSwitcher 的直接子节点上，
                    // 挂在里面的 Text 上不会触发动画。
                    child: Align(
                      key: ValueKey<String>(city),
                      alignment: alignment,
                      child: Text(
                        city,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: textAlign,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                          height: AppTypography.tightHeight,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _SwapButton extends StatelessWidget {
  const _SwapButton({
    required this.turn,
    required this.enabled,
    required this.onTap,
  });

  final Animation<double> turn;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Semantics(
          button: true,
          label: '交换出发地与目的地',
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              boxShadow: AppColors.chipShadow,
            ),
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: enabled ? onTap : null,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: RotationTransition(
                      turns: turn,
                      child: Icon(
                        Icons.sync,
                        size: 20,
                        color: enabled
                            ? AppColors.celadonDeep
                            : AppColors.crackle,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
