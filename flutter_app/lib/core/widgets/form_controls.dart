import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// 表单里的小标题，所有控件共用一份，避免同一个卡片里出现两种字重。
///
/// [trailing] 用来把状态写在标题这一行（例如「出行日期 · 明天」），
/// 这样控件本身不必再挤一个标签进去。
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: AppTypography.secondary,
                  fontWeight: FontWeight.w700,
                  color: AppColors.inkSoft,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

/// 「看起来是输入框、点开是弹层」的选择控件。
///
/// 出行日期与交通方式共用它。之前交通方式用的是
/// `DropdownButtonFormField`：收起态是青边圆角框，展开后却弹出一个
/// 没有任何主题的白色矩形列表，两套视觉完全不连着。这里换成自己实现的弹层，
/// 收起态展示的就是最终会被提交的那个值，展开态高亮的就是它。
class PickerField extends StatelessWidget {
  const PickerField({
    super.key,
    required this.value,
    required this.onTap,
    this.icon,
    this.enabled = true,
    this.semanticLabel,
  });

  /// 收起态显示的值，也是这次选择的结果。
  final String value;

  final VoidCallback onTap;

  /// 左侧图标，可以省略。半宽控件里一般省掉，把宽度留给文字。
  final IconData? icon;

  final bool enabled;

  /// 读屏用的完整描述。值本身很短（「2 天」），单独读会缺主语。
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius =
        BorderRadius.circular(AppSpacing.radiusControl);
    final Color foreground = enabled ? AppColors.ink : AppColors.crackle;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      child: Material(
        color: AppColors.surface,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: AppColors.hairline),
            ),
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(minHeight: AppSpacing.buttonHeight),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: <Widget>[
                    if (icon != null) ...<Widget>[
                      Icon(icon, size: 16, color: AppColors.celadon),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppTypography.body,
                          fontWeight: FontWeight.w700,
                          color: foreground,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.expand_more,
                      size: 18,
                      color: enabled ? AppColors.crackle : AppColors.hairline,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 弹层顶部的小横条。
///
/// Android 上没有 iOS 那种手势条，不给一点提示的话用户不知道这片面板能下滑关掉。
/// 所有自定义弹层共用同一个，避免每个弹层各画一条。
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.celadonPale,
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          ),
        ),
      );
}

/// 选择用的胶囊。
///
/// **故意不用 Material 的 `ChoiceChip` / `FilterChip`。**
/// 这两个组件在 M3 下选中态的底色与文字色分别取自 colorScheme 的不同角色，
/// 主题里只改其中一个（本项目在 chipTheme 里设了 secondaryLabelStyle）
/// 就会出现「深底 + 深字」，字被底色吃掉。真机上就是这么翻车的。
/// 这里把两种状态的前景色和背景色成对写死，对比度不再依赖组件的颜色推断。
class SelectChip extends StatelessWidget {
  const SelectChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.showCheck = false,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// 前置图标，用在「+ 自定义」这类动作型胶囊上。
  final IconData? icon;

  /// 选中时是否补一个对勾。多选（兴趣）用它，单选（体力）不用，
  /// 避免同一屏出现两种「选中」的读法。
  final bool showCheck;

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final Color background = !enabled
        ? AppColors.surfaceSunken
        : selected
            ? AppColors.celadonDeep
            : AppColors.surface;
    final Color foreground = !enabled
        ? AppColors.crackle
        : selected
            ? AppColors.onInk
            : AppColors.inkSoft;
    final Color border =
        selected ? AppColors.celadonDeep : AppColors.hairline;
    final BorderRadius radius = BorderRadius.circular(AppSpacing.radiusPill);

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      child: Material(
        color: background,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: border),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (icon != null) ...<Widget>[
                      Icon(icon, size: 15, color: foreground),
                      const SizedBox(width: 5),
                    ],
                    if (showCheck && selected) ...<Widget>[
                      Icon(Icons.check, size: 15, color: foreground),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: AppTypography.secondary,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w600,
                        color: foreground,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
