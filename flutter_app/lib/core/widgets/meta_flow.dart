import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// 一行「图标 + 文字」的事实，例如「≈43分钟」「来源 12306 MCP（…）」。
///
/// 文字必须是 [Flexible]：`Row` 默认给非弹性子项无限宽的主轴约束，
/// 只要调用方传进来一段长文本（车次来源、景区名），整行就会直接画到屏幕外。
/// 这一类「RIGHT OVERFLOWED」已经在两个页面各出现一次，所以防线放在组件里，
/// 而不是指望每个调用点自己记得加约束。
class MetaUnit extends StatelessWidget {
  const MetaUnit({
    super.key,
    required this.icon,
    required this.text,
    this.color,
    this.iconSize = 13,
    this.maxLines = 1,
  });

  final IconData icon;
  final String text;
  final Color? color;
  final double iconSize;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final Color tone = color ?? AppColors.crackle;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: iconSize, color: tone),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppTypography.caption,
              color: tone,
            ),
          ),
        ),
      ],
    );
  }
}

/// 把若干元信息摆成会自动换行的流式布局。
///
/// 约束链是这样的：`RenderWrap` 会把父级的 `maxWidth` 传给每一个子项，
/// 子项内部再用 [Flexible] 把文字收进这个上限。真正防止溢出的那一环
/// 在子项里，所以这里的约定是：**子项必须自带宽度收敛**，
/// 标准做法是 [MetaUnit]、[TagPill]、[DataStatusBadge]。
///
/// 这里刻意不使用 `LayoutBuilder`：行程页的 `RouteGauge` 依赖
/// `IntrinsicHeight` 绘制轨道，而 `LayoutBuilder` 无法提供内在尺寸，
/// 会在布局阶段直接抛异常。
class MetaFlow extends StatelessWidget {
  const MetaFlow({
    super.key,
    required this.children,
    this.spacing = 12,
    this.runSpacing = 6,
    this.alignment = WrapAlignment.start,
  });

  final List<Widget> children;
  final double spacing;
  final double runSpacing;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: spacing,
        runSpacing: runSpacing,
        alignment: alignment,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      );
}
