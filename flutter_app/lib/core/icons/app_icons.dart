import 'package:flutter/material.dart';

/// 全应用统一的图标资源登记处。
///
/// 设计稿以 PNG 提供，集中放在 `assets/icons/` 下并在这里登记：
/// 调用方只引用语义名（`AppIcons.like`），不直接写资源路径，
/// 换图或补一档尺寸时只改这一处。
///
/// 点赞与收藏有「前 / 后」两态：未选中用描边版，选中用填充版。
/// 其余图标（评论 / 上传 / 举报）只有单态。
abstract final class AppIcons {
  static const String _base = 'assets/icons/';

  static const String likeOutline = '${_base}ic_like_outline.png';
  static const String likeFilled = '${_base}ic_like_filled.png';
  static const String favoriteOutline = '${_base}ic_favorite_outline.png';
  static const String favoriteFilled = '${_base}ic_favorite_filled.png';
  static const String comment = '${_base}ic_comment.png';
  static const String upload = '${_base}ic_upload.png';
  static const String report = '${_base}ic_report.png';

  // 首页快捷入口：使用团队提供的中原文化图标，不再使用普通 Material 图标。
  static const String discover = '${_base}ic_discover.png';
  static const String nearby = '${_base}ic_nearby.png';
  static const String planning = '${_base}ic_planning.png';
  static const String culture = '${_base}ic_culture.png';

  // 首页区块标题：同样是团队提供的图标，和上面的快捷入口同一套画风。
  static const String route = '${_base}ic_route.png';
  static const String featured = '${_base}ic_featured.png';
  static const String more = '${_base}ic_more.png';

  // 「从一个场景开始」的四个场景。
  static const String sceneWeekend = '${_base}ic_scene_weekend.png';
  static const String sceneAncient = '${_base}ic_scene_ancient.png';
  static const String sceneNature = '${_base}ic_scene_nature.png';
  static const String sceneFood = '${_base}ic_scene_food.png';

  /// 首页左上角的品牌标：就是 APK 自己的图标。
  static const String logo = 'assets/brand/logo_mark.png';

  /// 点赞前后两态。
  static String like({required bool selected}) =>
      selected ? likeFilled : likeOutline;

  /// 收藏（星标）前后两态。
  static String favorite({required bool selected}) =>
      selected ? favoriteFilled : favoriteOutline;
}

/// 统一尺寸与着色的图标。
///
/// 源图是单色描边，因此用 [BlendMode.srcIn] 上色：既能跟随主题色
/// （例如点赞后变朱砂红），也不会像 `colorFilter` 那样丢掉半透明边缘。
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.asset, {
    super.key,
    this.size = 18,
    this.color,
    this.semanticLabel,
  });

  final String asset;
  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Image.asset(
        asset,
        width: size,
        height: size,
        color: color,
        colorBlendMode: color == null ? null : BlendMode.srcIn,
        filterQuality: FilterQuality.medium,
        semanticLabel: semanticLabel,
        excludeFromSemantics: semanticLabel != null,
      );
}
