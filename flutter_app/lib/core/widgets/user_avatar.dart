import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 用户头像。
///
/// 两种来源的优先级只写在这一处：有 [imageUrl] 就显示上传的照片，没有才回落到
/// [avatarKey] 的预设图案。每个调用点各写一遍 if/else 的话，早晚会有一处把
/// "已经换了照片"的用户又画成一朵花。
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.avatarKey,
    this.size = 30,
    this.borderColor,
  });

  /// 用于无障碍标签。头像本身是图形，读屏软件需要知道"这是谁的头像"。
  final String name;

  /// 已经解析成本机可访问的地址；空值表示没有自定义头像。
  final String? imageUrl;
  final String? avatarKey;
  final double size;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final String url = imageUrl?.trim() ?? '';
    return Semantics(
      image: true,
      label: '$name 的头像',
      child: Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.celadonPale,
          border: Border.all(color: borderColor ?? AppColors.surface, width: 1.5),
        ),
        alignment: Alignment.center,
        child: url.isEmpty
            ? _preset
            : CachedNetworkImage(
                imageUrl: url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 160),
                // 图片加载不出来时回到预设图案，而不是留一个碎图图标。
                errorWidget: (_, __, ___) => _preset,
                placeholder: (_, __) => const SizedBox.shrink(),
              ),
      ),
    );
  }

  Widget get _preset => Icon(
        _icon(avatarKey),
        size: size * 0.52,
        color: AppColors.celadonDeep,
      );

  static IconData _icon(String? key) => switch (key) {
        'kiln' => Icons.account_balance_outlined,
        'amber' => Icons.wb_sunny_outlined,
        'river' => Icons.water_outlined,
        'ink' => Icons.auto_awesome_outlined,
        _ => Icons.landscape_outlined,
      };
}
