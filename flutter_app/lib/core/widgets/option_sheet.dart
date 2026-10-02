import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'form_controls.dart';

/// 通用单选弹层。
///
/// 交通方式用它。之前这里挂的是 `DropdownButtonFormField`：收起态是「青边 +
/// 圆角 + 14 号粗体」，点开后却是一块没有主题的白色矩形列表，选中项只用灰底表示，
/// 展开前后像两个不同产品里的控件。换成统一弹层之后，收起态展示的值、
/// 展开态勾选的那一行、以及选择的结果是同一个字符串，不存在对不上的可能。
Future<String?> showOptionSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<String> options,
  required String selected,
  Map<String, String> details = const <String, String>{},
}) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => _OptionSheet(
        title: title,
        subtitle: subtitle,
        options: options,
        selected: selected,
        details: details,
      ),
    );

class _OptionSheet extends StatelessWidget {
  const _OptionSheet({
    required this.title,
    required this.subtitle,
    required this.options,
    required this.selected,
    required this.details,
  });

  final String title;
  final String? subtitle;
  final List<String> options;
  final String selected;
  final Map<String, String> details;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SheetHandle(),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: AppTypography.sectionTitle,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
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
                const SizedBox(height: 14),
                for (final String option in options) ...<Widget>[
                  _OptionTile(
                    label: option,
                    detail: details[option],
                    selected: option == selected,
                    onTap: () => Navigator.of(context).pop(option),
                  ),
                  if (option != options.last) const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
      );
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.label,
    required this.detail,
    required this.selected,
    required this.onTap,
  });

  final String label;

  /// 一行解释。选项名本身说明不了代价（「自驾」意味着停车和油费），
  /// 这一行是用来做决定的，不是装饰。
  final String? detail;

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius =
        BorderRadius.circular(AppSpacing.radiusControl);
    return Semantics(
      button: true,
      selected: selected,
      label: detail == null ? label : '$label，$detail',
      child: Material(
        color: selected ? AppColors.surfaceTint : AppColors.surface,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: selected ? AppColors.celadon : AppColors.hairline,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: AppTypography.body,
                            fontWeight: FontWeight.w700,
                            color: selected
                                ? AppColors.celadonDeep
                                : AppColors.ink,
                          ),
                        ),
                        if (detail != null) ...<Widget>[
                          const SizedBox(height: 2),
                          Text(
                            detail!,
                            style: const TextStyle(
                              fontSize: AppTypography.caption,
                              color: AppColors.crackle,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: selected ? AppColors.celadonDeep : AppColors.hairline,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
