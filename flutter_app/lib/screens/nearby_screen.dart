import 'package:flutter/material.dart';

import '../core/formatters/distance_text.dart';
import '../core/location/location_service.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/widgets/app_back_button.dart';
import '../core/widgets/city_picker_sheet.dart';
import '../core/widgets/photo_plate.dart';
import '../core/widgets/surface_card.dart';
import '../data/repositories/travel_repository.dart';
import '../models/travel_models.dart';
import 'additional_screens.dart';

/// 这一屏此刻在做什么。
enum _NearbyPhase {
  /// 正在取设备坐标（含权限申请）。
  locating,

  /// 坐标到手了，正在问服务端。
  loading,

  /// 拿到了一份附近结果（也可能是"附近没有"）。
  ready,

  /// 定位没拿到 —— 权限、系统开关或取坐标失败。
  blocked,

  /// 定位成功但服务端没答上来。
  failed,

  /// 用户选择了按城市浏览。
  city,
}

/// 「附近的景点」。
///
/// 这一页的立场：**拒绝授权不是死路**。
/// 定位拿不到时，页面把重心从「再给我一次权限」挪到「按城市浏览」——
/// 后一条路同样能把人送到景点详情，而且不需要任何权限。
/// 一个把没授权的人关在门外的功能，本身就不该出现在这个项目里。
class NearbyScreen extends StatefulWidget {
  const NearbyScreen({
    super.key,
    required this.repository,
    this.locations = const LocationService(),
  });

  final TravelRepository repository;

  /// 注入点：真机上就是 geolocator，测试里可以换掉。
  final LocationService locations;

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  _NearbyPhase _phase = _NearbyPhase.locating;

  /// 给用户看的一句话。成功时不显示。
  String _notice = '';

  List<NearbyHit> _hits = const <NearbyHit>[];
  int _radiusMeters = TravelRepository.defaultNearbyRadiusMeters;

  /// 上架了但没配坐标、因此没参与计算的景点数。
  int _skipped = 0;

  /// 这一次挡住我们的是用户自己的选择（而不是网络）。界面据此改变重心。
  bool _blockedByPermission = false;
  LocationReadiness? _readiness;

  String? _city;
  List<Destination> _cityItems = const <Destination>[];

  /// 城市浏览这条路上有没有踩到网络问题（缓存或演示内容）。
  bool _cityDegraded = false;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  Future<void> _locate() async {
    setState(() {
      _phase = _NearbyPhase.locating;
      _notice = '';
      _hits = const <NearbyHit>[];
      _skipped = 0;
      _blockedByPermission = false;
      _readiness = null;
      _city = null;
      _cityItems = const <Destination>[];
      _cityDegraded = false;
    });

    final LocationAttempt attempt = await widget.locations.currentFix();
    if (!mounted) {
      return;
    }
    if (!attempt.hasFix) {
      setState(() {
        _phase = _NearbyPhase.blocked;
        _notice = attempt.message;
        _blockedByPermission = attempt.blockedByPermission;
        _readiness = attempt.readiness;
      });
      return;
    }

    setState(() => _phase = _NearbyPhase.loading);
    final NearbySearchResult result = await widget.repository.fetchNearby(
      lng: attempt.fix!.lng,
      lat: attempt.fix!.lat,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _radiusMeters = result.radiusMeters;
      _skipped = result.skippedWithoutCoordinate;
      if (result.failure != null) {
        _phase = _NearbyPhase.failed;
        _notice = result.failure!.message;
        _hits = const <NearbyHit>[];
        return;
      }
      _phase = _NearbyPhase.ready;
      _hits = result.items;
    });
  }

  /// 降级路径：不用定位，按城市浏览。
  ///
  /// 走的还是同一个景点库（`/pois?city=`），所以卡片、详情页、收藏全都一致，
  /// 不是另做一套"简化版"给人看。
  Future<void> _browseCity(String city) async {
    setState(() {
      _city = city;
      _phase = _NearbyPhase.loading;
      _cityItems = const <Destination>[];
      _cityDegraded = false;
    });
    final CatalogResult result =
        await widget.repository.fetchDestinations(city: city);
    if (!mounted) {
      return;
    }
    setState(() {
      _cityItems = result.destinations;
      _cityDegraded = result.failure != null;
      _phase = _NearbyPhase.city;
    });
  }

  Future<void> _pickCity() async {
    final String? picked = await showCityPickerSheet(
      context,
      title: '选择城市',
      selected: _city ?? '',
    );
    if (picked == null || picked.isEmpty || !mounted) {
      return;
    }
    await _browseCity(picked);
  }

  void _openDetail(Destination destination) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DestinationDetail(destination: destination),
      ),
    );
  }

  Future<void> _openSettings() async {
    if (_readiness == LocationReadiness.serviceOff) {
      await widget.locations.openLocationSettings();
    } else {
      await widget.locations.openAppSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    final double page = AppSpacing.pageFor(MediaQuery.sizeOf(context).width);
    return Scaffold(
      backgroundColor: AppColors.ground,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('附近的景点'),
        backgroundColor: AppColors.ground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(top: false, child: _body(page)),
    );
  }

  Widget _body(double page) {
    switch (_phase) {
      case _NearbyPhase.locating:
      case _NearbyPhase.loading:
        return _BusyView(
          title: _phase == _NearbyPhase.locating ? '正在获取位置' : '正在找附近的景点',
          detail: _phase == _NearbyPhase.locating
              ? '位置只用于这一次查询，不会保存，也不会上传历史。'
              : '按直线距离排序，只算已经配好坐标的景点。',
        );
      case _NearbyPhase.blocked:
      case _NearbyPhase.failed:
        return ListView(
          padding: EdgeInsets.fromLTRB(page, 8, page, 32),
          children: <Widget>[
            _FallbackPanel(
              notice: _notice,
              blockedByPermission: _blockedByPermission,
              readiness: _readiness,
              onRetry: _locate,
              onBrowseCity: _pickCity,
              onOpenSettings: _openSettings,
            ),
          ],
        );
      case _NearbyPhase.city:
        return _cityView(page);
      case _NearbyPhase.ready:
        return _nearbyView(page);
    }
  }

  Widget _nearbyView(double page) => ListView(
        padding: EdgeInsets.fromLTRB(page, 8, page, 32),
        children: <Widget>[
          _SearchSummary(
            found: _hits.length,
            radiusMeters: _radiusMeters,
            skippedWithoutCoordinate: _skipped,
          ),
          const SizedBox(height: AppSpacing.content),
          if (_hits.isEmpty)
            const _QuietNote(
              text: '这个范围内暂时没有已收录的景点。可以换个城市看看，'
                  '或者回到首页按主题挑一条走廊。',
            )
          else
            for (final NearbyHit hit in _hits)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.content),
                child: _NearbyCard(
                  destination: hit.destination,
                  distanceMeters: hit.distanceMeters,
                  onTap: () => _openDetail(hit.destination),
                ),
              ),
          const SizedBox(height: AppSpacing.small),
          const _FinePrint(
            text: '距离是直线距离，不是步行或驾车里程。'
                '票价与开放时间以景区官方公告为准。',
          ),
          const SizedBox(height: AppSpacing.section),
          _GhostAction(
            label: '换个方式：按城市浏览',
            icon: Icons.location_city_outlined,
            onTap: _pickCity,
            width: double.infinity,
          ),
        ],
      );

  Widget _cityView(double page) => ListView(
        padding: EdgeInsets.fromLTRB(page, 8, page, 32),
        children: <Widget>[
          _CityHeader(
            city: _city ?? '',
            count: _cityItems.length,
            degraded: _cityDegraded,
          ),
          const SizedBox(height: AppSpacing.content),
          if (_cityItems.isEmpty)
            const _QuietNote(text: '这个城市还没有收录景点。换一个城市试试。')
          else
            for (final Destination item in _cityItems)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.content),
                child: _NearbyCard(
                  destination: item,
                  onTap: () => _openDetail(item),
                ),
              ),
          const SizedBox(height: AppSpacing.section),
          _GhostAction(
            label: '重新定位',
            icon: Icons.my_location,
            onTap: _locate,
            width: double.infinity,
          ),
        ],
      );
}

/// 正在做事的两个时刻共用的安静视图。
///
/// 不写成「转圈 + 无文案」：这一屏要申请定位权限，用户有权知道应用此刻
/// 在做什么、以及位置会被怎么处理。
class _BusyView extends StatelessWidget {
  const _BusyView({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.celadon,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: const TextStyle(
                  fontSize: AppTypography.cardTitle,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: AppTypography.secondary,
                  height: AppTypography.lineHeight,
                  color: AppColors.inkSoft,
                ),
              ),
            ],
          ),
        ),
      );
}

/// 定位或网络没成事时的面板。
///
/// 「按城市浏览」永远排在第一位：它是这一页真正的保底路径，
/// 不是"实在不行你再试试"的安慰按钮。
class _FallbackPanel extends StatelessWidget {
  const _FallbackPanel({
    required this.notice,
    required this.blockedByPermission,
    required this.readiness,
    required this.onRetry,
    required this.onBrowseCity,
    required this.onOpenSettings,
  });

  final String notice;
  final bool blockedByPermission;
  final LocationReadiness? readiness;
  final Future<void> Function() onRetry;
  final Future<void> Function() onBrowseCity;
  final Future<void> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    // 只有「永久拒绝」和「系统开关关着」这两种情况，去系统设置才真的有用。
    // 其余情况把按钮摆出来只会让人白点一次。
    final bool canOpenSettings =
        readiness == LocationReadiness.refusedForever ||
            readiness == LocationReadiness.serviceOff;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                blockedByPermission
                    ? Icons.location_off_outlined
                    : Icons.cloud_off_outlined,
                size: 20,
                color: AppColors.celadonDeep,
              ),
              const SizedBox(width: 8),
              Text(
                blockedByPermission ? '这次没用上定位' : '这次没连上',
                style: const TextStyle(
                  fontSize: AppTypography.cardTitle,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            notice,
            style: const TextStyle(
              fontSize: AppTypography.body,
              height: AppTypography.lineHeight,
              color: AppColors.inkSoft,
            ),
          ),
          const SizedBox(height: 18),
          _PrimaryAction(
            label: '按城市浏览景点',
            icon: Icons.location_city_outlined,
            onTap: onBrowseCity,
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: _GhostAction(
                  label: '重新定位',
                  icon: Icons.my_location,
                  onTap: onRetry,
                ),
              ),
              if (canOpenSettings) ...<Widget>[
                const SizedBox(width: 10),
                Expanded(
                  child: _GhostAction(
                    label: '系统设置',
                    icon: Icons.settings_outlined,
                    onTap: onOpenSettings,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// 结果抬头：范围内找到几个，以及"有几个没能参与计算"。
class _SearchSummary extends StatelessWidget {
  const _SearchSummary({
    required this.found,
    required this.radiusMeters,
    required this.skippedWithoutCoordinate,
  });

  final int found;
  final int radiusMeters;
  final int skippedWithoutCoordinate;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '${distanceText(radiusMeters)}内找到 $found 个景点',
              style: const TextStyle(
                fontSize: AppTypography.sectionTitle,
                fontWeight: FontWeight.w700,
                height: AppTypography.headingHeight,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '按直线距离从近到远排。',
              style: TextStyle(
                fontSize: AppTypography.secondary,
                color: AppColors.inkSoft,
              ),
            ),
            if (skippedWithoutCoordinate > 0) ...<Widget>[
              const SizedBox(height: 8),
              // 这一行是给运营看的，也是给用户看的：不说的话，
              //「附近只有 2 个景点」和「还有 5 个没配坐标」长得一模一样。
              Text(
                '另有 $skippedWithoutCoordinate 个景点还没配坐标，这次没能参与计算。',
                style: const TextStyle(
                  fontSize: AppTypography.caption,
                  height: AppTypography.lineHeight,
                  color: AppColors.inkSoft,
                ),
              ),
            ],
          ],
        ),
      );
}

class _CityHeader extends StatelessWidget {
  const _CityHeader({
    required this.city,
    required this.count,
    required this.degraded,
  });

  final String city;
  final int count;
  final bool degraded;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '$city · 已收录 $count 个景点',
              style: const TextStyle(
                fontSize: AppTypography.sectionTitle,
                fontWeight: FontWeight.w700,
                height: AppTypography.headingHeight,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              degraded
                  ? '网络不可用，下面这些来自本机缓存或演示内容，不是实时结果。'
                  : '内容由运营台维护，改完即刻生效。',
              style: TextStyle(
                fontSize: AppTypography.secondary,
                height: AppTypography.lineHeight,
                color: degraded ? AppColors.celadonDeep : AppColors.inkSoft,
              ),
            ),
          ],
        ),
      );
}

class _QuietNote extends StatelessWidget {
  const _QuietNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        color: AppColors.surfaceTint,
        shadow: const <BoxShadow>[],
        child: Text(
          text,
          style: const TextStyle(
            fontSize: AppTypography.body,
            height: AppTypography.lineHeight,
            color: AppColors.inkSoft,
          ),
        ),
      );
}

/// 小字说明。用于口径声明，不用来做装饰。
class _FinePrint extends StatelessWidget {
  const _FinePrint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: AppTypography.caption,
          height: AppTypography.lineHeight,
          color: AppColors.inkSoft,
        ),
      );
}

/// 一张景点卡。
///
/// 和发现页的卡片同一套信息口径：图、名、城市·主题、一句话介绍、票价与时长；
/// 差别只是这里多了一个距离徽标 —— 而距离只在真有坐标时出现。
class _NearbyCard extends StatelessWidget {
  const _NearbyCard({
    required this.destination,
    this.distanceMeters,
    required this.onTap,
  });

  final Destination destination;
  final int? distanceMeters;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        onTap: onTap,
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 撑满卡片宽度：不指定宽度时，图片会按自身比例决定占多宽，
            // 同一列卡片就会一张宽一张窄。
            SizedBox(
              width: double.infinity,
              child: PhotoPlate(
                url: destination.image,
                height: AppSpacing.photoHeight,
                scrim: true,
                fallbackLabel: destination.name,
                semanticLabel: destination.name,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          destination.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: AppTypography.cardTitle,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      if (distanceMeters != null) ...<Widget>[
                        const SizedBox(width: 8),
                        _DistanceChip(meters: distanceMeters!),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${destination.city} · ${destination.theme}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AppTypography.secondary,
                      color: AppColors.inkSoft,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    destination.summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AppTypography.body,
                      height: AppTypography.lineHeight,
                      color: AppColors.inkSoft,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      _Fact(
                        text: destination.ticket <= 0
                            ? '免票参考'
                            : '¥${destination.ticket} 起',
                      ),
                      const SizedBox(width: 14),
                      Flexible(child: _Fact(text: destination.duration)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

/// 距离徽标。数字用等宽字形，一列卡片扫下来时不会左右跳。
class _DistanceChip extends StatelessWidget {
  const _DistanceChip({required this.meters});

  final int meters;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.celadonPale,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        ),
        child: Text(
          distanceText(meters),
          style: const TextStyle(
            fontSize: AppTypography.secondary,
            fontWeight: FontWeight.w700,
            color: AppColors.celadonDeep,
            fontFeatures: AppTypography.tabularFigures,
          ),
        ),
      );
}

class _Fact extends StatelessWidget {
  const _Fact({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: AppTypography.secondary,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
          fontFeatures: AppTypography.tabularFigures,
        ),
      );
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: AppSpacing.buttonHeight,
        child: FilledButton.icon(
          onPressed: () => onTap(),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.celadonDeep,
            foregroundColor: AppColors.onInk,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
            ),
          ),
          icon: Icon(icon, size: 18),
          label: Text(
            label,
            style: const TextStyle(
              fontSize: AppTypography.body,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
}

class _GhostAction extends StatelessWidget {
  const _GhostAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.width,
  });

  final String label;
  final IconData icon;
  final Future<void> Function() onTap;
  final double? width;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        height: AppSpacing.buttonHeight,
        child: OutlinedButton.icon(
          onPressed: () => onTap(),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.celadonDeep,
            side: const BorderSide(color: AppColors.celadonPale),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
            ),
          ),
          icon: Icon(icon, size: 18),
          label: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: AppTypography.body,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
}
