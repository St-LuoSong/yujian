import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/network/api_failure.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/data_status_badge.dart';
import '../../core/widgets/surface_card.dart';
import '../../models/map_models.dart';
import '../../models/travel_models.dart';

/// 行程地图卡片。
///
/// 设计取舍（写在代码里，避免以后被「优化」掉）：
///
/// 1. **底图由服务端取**。APK 里没有百度 AK，也没有百度 SDK；
///    服务端把 1024 像素的底图连同「每个站点应该画在哪一像素」一起给出来。
/// 2. **拖动不猜坐标**。手指移动时先在本地平移画面（跟手、不掉帧），
///    松手后把「视野中心移动了多少像素」交给服务端换算成新的中心点，
///    投影公式因此只有服务端一份实现。
/// 3. **不出现空地图**。服务端明确降级、网络失败、或这份方案本来就不在服务器上时，
///    这里都会换成当天的文字路线，并且说清楚为什么。
/// 4. **不覆盖百度的版权水印**。底图左下角自带「百度地图」标识，
///    所以本卡片自己的标注放在右下角，控件放在右侧中部。
class RouteMapCard extends ConsumerStatefulWidget {
  const RouteMapCard({
    super.key,
    required this.planId,
    required this.days,
    this.onLocateStop,
  });

  /// 服务端行程 id。为空表示这是内置演示方案，主流程直接走文字路线。
  final String? planId;

  /// 方案的每一天，用来出日期切换与降级时的文字路线。
  final List<PlanDay> days;

  /// 点了「时间轴」之后回调：(第几天(0 基), 站点标题)。
  final void Function(int dayIndex, String title)? onLocateStop;

  @override
  ConsumerState<RouteMapCard> createState() => _RouteMapCardState();
}

class _RouteMapCardState extends ConsumerState<RouteMapCard> {
  /// 手指移动不到这个距离就当成点击。
  static const double _dragTolerance = 12;
  /// 超过这个时长就不再算点击，避免长按被误判。
  static const int _tapMaxMillis = 400;

  int _dayIndex = 0;
  RouteMapSnapshot? _snapshot;
  ApiFailure? _failure;
  bool _loading = false;
  bool _degraded = false;
  int? _selectedIndex;

  /// 拖动过程中的本地平移量，松手后清空并重新取图。
  Offset _dragPreview = Offset.zero;
  late Offset _gestureStart;
  late DateTime _gestureStartedAt;
  double _gestureMove = 0;
  double _gestureScale = 1;
  double _mapWidth = 1;

  @override
  void initState() {
    super.initState();
    unawaited(_loadDay(0, replace: true));
  }

  RouteMapViewport? get _viewport => _snapshot?.viewport;

  /// 取一份新的快照。
  ///
  /// [panX] / [panY] 传的是「视野中心位移」：手指向右拖时中心向西移动，因此调用方取负号。
  Future<void> _loadDay(
    int dayIndex, {
    bool replace = false,
    double? panX,
    double? panY,
    int? zoom,
    bool reset = false,
  }) async {
    final String? planId = widget.planId;
    final RouteMapViewport? previous = _snapshot?.viewport;
    if (planId == null || planId.isEmpty) {
      setState(() {
        _dayIndex = dayIndex;
        _snapshot = null;
        _failure = null;
        _degraded = true;
      });
      return;
    }
    final bool keepViewport = !reset && (panX != null || zoom != null);
    setState(() {
      _dayIndex = dayIndex;
      _loading = true;
      _failure = null;
      _dragPreview = Offset.zero;
      if (replace || reset) {
        _snapshot = null;
      }
    });
    try {
      final RouteMapSnapshot snapshot = await ref.read(travelRepositoryProvider).fetchRouteMap(
            planId: planId,
            day: dayIndex + 1,
            centerLng: keepViewport ? previous?.centerLng : null,
            centerLat: keepViewport ? previous?.centerLat : null,
            zoom: reset ? null : (zoom ?? (panX == null ? null : previous?.zoom)),
            panX: panX,
            panY: panY,
          );
      if (!mounted) {
        return;
      }
      if (snapshot.hasImage) {
        await _precache(snapshot.imageUrl);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _snapshot = snapshot;
        _loading = false;
        _degraded = snapshot.fallback;
        _selectedIndex = null;
      });
    } on ApiFailure catch (failure) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _failure = failure;
        _degraded = true;
      });
    }
  }

  /// 先把新底图放进缓存，再切换界面。
  ///
  /// 少了这一步，每次拖动松手都会先看到占位图再「跳」出地图。
  Future<void> _precache(String url) async {
    try {
      await precacheImage(CachedNetworkImageProvider(url), context);
    } catch (_) {
      // 预取失败不影响主流程：正式渲染时会再试一次，失败则由 errorWidget 兜底。
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    _gestureStart = details.localFocalPoint;
    _gestureStartedAt = DateTime.now();
    _gestureMove = 0;
    _gestureScale = 1;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final Offset delta = details.localFocalPoint - _gestureStart;
    _gestureScale = details.scale;
    if (delta.distance > _gestureMove) {
      _gestureMove = delta.distance;
    }
    setState(() => _dragPreview = delta);
  }

  void _onScaleEnd(ScaleEndDetails details) {
    final int held = DateTime.now().difference(_gestureStartedAt).inMilliseconds;
    final Offset delta = _dragPreview;
    final double scale = _gestureScale;
    setState(() => _dragPreview = Offset.zero);

    if (_gestureMove < _dragTolerance && held < _tapMaxMillis) {
      _handleTap(_gestureStart);
      return;
    }
    if (scale > 1.25) {
      unawaited(_zoomBy(1));
      return;
    }
    if (scale < 0.8) {
      unawaited(_zoomBy(-1));
      return;
    }
    final RouteMapViewport? viewport = _viewport;
    if (viewport == null || delta == Offset.zero) {
      return;
    }
    final Size size = _displayedSize(viewport);
    unawaited(_loadDay(
      _dayIndex,
      panX: -delta.dx * viewport.width / size.width,
      panY: -delta.dy * viewport.height / size.height,
    ));
  }

  /// 底图在屏幕上的显示尺寸：宽高比固定取自服务端，保证像素坐标严格对应。
  Size _displayedSize(RouteMapViewport viewport) =>
      Size(_mapWidth, _mapWidth * viewport.height / viewport.width);

  Future<void> _zoomBy(int step) async {
    final RouteMapViewport? viewport = _viewport;
    if (viewport == null) {
      return;
    }
    final int next = (viewport.zoom + step).clamp(3, 19);
    if (next == viewport.zoom) {
      return;
    }
    await _loadDay(_dayIndex, zoom: next);
  }

  void _handleTap(Offset localPosition) {
    final RouteMapSnapshot? snapshot = _snapshot;
    final RouteMapViewport? viewport = snapshot?.viewport;
    if (snapshot == null || viewport == null) {
      return;
    }
    final Size size = _displayedSize(viewport);
    final double sx = size.width / viewport.width;
    final double sy = size.height / viewport.height;
    int? hit;
    double best = 30;
    for (final RouteMapMarker marker in snapshot.markers) {
      if (!marker.inside) {
        continue;
      }
      final Offset spot = Offset(marker.x * sx, marker.y * sy);
      final double distance = (spot - localPosition).distance;
      if (distance < best) {
        best = distance;
        hit = marker.index;
      }
    }
    setState(() => _selectedIndex = hit);
  }

  RouteMapMarker? get _selected {
    final RouteMapSnapshot? snapshot = _snapshot;
    if (snapshot == null || _selectedIndex == null) {
      return null;
    }
    for (final RouteMapMarker marker in snapshot.markers) {
      if (marker.index == _selectedIndex) {
        return marker;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final RouteMapSnapshot? snapshot = _snapshot;
    return SurfaceCard(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _header(),
          if (widget.days.length > 1) ...<Widget>[
            const SizedBox(height: AppSpacing.content),
            _dayChips(),
          ],
          const SizedBox(height: AppSpacing.content),
          _body(),
          if (_selected != null) ...<Widget>[
            const SizedBox(height: AppSpacing.content),
            _selectedStrip(_selected!),
          ],
          if (!_degraded && snapshot != null && snapshot.unplaced.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.content),
            _unplacedBlock(snapshot.unplaced),
          ],
        ],
      ),
    );
  }

  Widget _header() => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.map_outlined, size: 18, color: AppColors.celadonDeep),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  '路线地图',
                  style: TextStyle(
                    fontSize: AppTypography.cardTitle,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _subtitle(),
                  style: const TextStyle(
                    fontSize: AppTypography.caption,
                    color: AppColors.crackle,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (_snapshot != null) ...<Widget>[
            const SizedBox(width: 8),
            // 刻意不传 queriedAt。之前带上它时，卡片写着"实时数据（23:49 更新）"，
            // 但那个时刻只是"用户打开地图的时间"，底图是静态的、不含实时路况。
            // 现在的口径是底图与坐标的资料来源（系统资料），更新时间不冒充数据新鲜度。
            DataStatusBadge(
              status: _snapshot!.status,
              dense: true,
            ),
          ],
        ],
      );

  String _subtitle() {
    if (widget.planId == null || widget.planId!.isEmpty) {
      return '本地演示方案，地图需要连接服务器';
    }
    if (_loading && _snapshot == null) {
      return '正在取底图与站点坐标…';
    }
    if (_degraded) {
      return '底图暂不可用，这里按文字路线展示当天的安排';
    }
    final RouteMapMarker? selected = _selected;
    if (selected != null) {
      return '已选中第 ${selected.index} 站，时间轴中会同步高亮';
    }
    return '拖动移动画面，点圆点看是第几站';
  }

  Widget _dayChips() => Wrap(
        spacing: AppSpacing.small,
        runSpacing: AppSpacing.small,
        children: <Widget>[
          for (int i = 0; i < widget.days.length; i++) _dayChip(i),
        ],
      );

  Widget _dayChip(int index) {
    final bool active = index == _dayIndex;
    return Semantics(
      button: true,
      selected: active,
      label: '第 ${index + 1} 天路线',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        onTap: active ? null : () => unawaited(_loadDay(index, replace: true)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: active ? AppColors.celadonDeep : AppColors.surfaceTint,
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          ),
          child: Text(
            'DAY ${(index + 1).toString().padLeft(2, '0')}',
            style: TextStyle(
              fontSize: AppTypography.caption,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: active ? AppColors.onInk : AppColors.celadonDeep,
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    final RouteMapSnapshot? snapshot = _snapshot;
    final RouteMapViewport? viewport = snapshot?.viewport;
    if (snapshot == null || !snapshot.hasImage || viewport == null) {
      return _fallbackRoute();
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        _mapWidth = constraints.maxWidth;
        final Size size = _displayedSize(viewport);
        final double sx = size.width / viewport.width;
        final double sy = size.height / viewport.height;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  onScaleEnd: _onScaleEnd,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      _mapLayer(snapshot, size, sx, sy),
                      if (_loading)
                        const Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: LinearProgressIndicator(
                            minHeight: 3,
                            color: AppColors.celadon,
                            backgroundColor: Colors.transparent,
                          ),
                        ),
                      Positioned(right: 10, bottom: 10, child: _attribution()),
                      Positioned(right: 10, top: 10, child: _controls(viewport)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _legend(snapshot),
          ],
        );
      },
    );
  }

  /// 底图 + 折线 + 标记，一起按 [_dragPreview] 平移，做到「跟手」。
  Widget _mapLayer(RouteMapSnapshot snapshot, Size size, double sx, double sy) {
    return Transform.translate(
      offset: _dragPreview,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          CachedNetworkImage(
            imageUrl: snapshot.imageUrl,
            fit: BoxFit.fill,
            fadeInDuration: const Duration(milliseconds: 180),
            placeholder: (_, __) => const ColoredBox(color: AppColors.surfaceTint),
            errorWidget: (_, __, ___) => const ColoredBox(
              color: AppColors.surfaceTint,
              child: Center(
                child: Text(
                  '底图加载失败，请检查网络后重试',
                  style: TextStyle(fontSize: AppTypography.caption, color: AppColors.crackle),
                ),
              ),
            ),
          ),
          CustomPaint(
            size: size,
            painter: _RoutePainter(
              points: snapshot.polyline
                  .map((Offset point) => Offset(point.dx * sx, point.dy * sy))
                  .toList(),
              color: AppColors.celadonDeep,
            ),
          ),
          for (final RouteMapMarker marker in snapshot.markers)
            if (marker.inside)
              Positioned(
                left: marker.x * sx - 17,
                top: marker.y * sy - 17,
                width: 34,
                height: 34,
                child: Center(child: _markerDot(marker)),
              ),
        ],
      ),
    );
  }

  Widget _markerDot(RouteMapMarker marker) {
    final bool active = marker.index == _selectedIndex;
    final double size = active ? 34 : 28;
    return Semantics(
      label: '第 ${marker.index} 站 ${marker.title}',
      button: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: active ? AppColors.kilnRed : AppColors.celadonDeep,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: active ? 3 : 2.5),
          boxShadow: const <BoxShadow>[
            BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 2)),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          marker.index.toString(),
          style: TextStyle(
            fontSize: active ? 14 : 12,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            fontFeatures: AppTypography.tabularFigures,
          ),
        ),
      ),
    );
  }

  Widget _controls(RouteMapViewport viewport) => DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
          boxShadow: AppColors.chipShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _mapButton(icon: Icons.add, label: '放大', onTap: () => unawaited(_zoomBy(1))),
            _mapButton(icon: Icons.remove, label: '缩小', onTap: () => unawaited(_zoomBy(-1))),
            _mapButton(
              icon: Icons.center_focus_strong_outlined,
              label: '回到全览',
              onTap: viewport.fitted ? null : () => unawaited(_loadDay(_dayIndex, reset: true)),
            ),
          ],
        ),
      );

  Widget _mapButton({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) =>
      Tooltip(
        message: label,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              icon,
              size: 20,
              color: onTap == null ? AppColors.crackle : AppColors.celadonDeep,
            ),
          ),
        ),
      );

  /// 只保留底图自带的版权标识，这里补一句「不含实时路况」。
  ///
  /// 位置刻意放在右下角：百度水印在底图左下角，盖住它既不合规也没必要。
  Widget _attribution() => DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Text(
            '静态底图 · 不含实时路况',
            style: TextStyle(fontSize: 10, color: AppColors.inkSoft),
          ),
        ),
      );

  Widget _legend(RouteMapSnapshot snapshot) {
    final int inside = snapshot.markers.where((RouteMapMarker m) => m.inside).length;
    return Text(
      '共 ${snapshot.markers.length} 个可定位站点，当前画面内 $inside 个 · 来源：${snapshot.source}',
      style: const TextStyle(
        fontSize: AppTypography.caption,
        color: AppColors.crackle,
        height: 1.45,
      ),
    );
  }

  Widget _selectedStrip(RouteMapMarker marker) => DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surfaceTint,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.content),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                  color: AppColors.kilnRed,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  marker.index.toString(),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      marker.title,
                      style: const TextStyle(
                        fontSize: AppTypography.body,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      <String>[
                        if (marker.time.isNotEmpty) marker.time,
                        if (marker.coordinateSource.isNotEmpty) marker.coordinateSource,
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: AppTypography.caption,
                        color: AppColors.crackle,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.onLocateStop != null)
                TextButton(
                  onPressed: () => widget.onLocateStop!(_dayIndex, marker.title),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.celadonDeep,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, AppSpacing.minTouchTarget),
                  ),
                  child: const Text(
                    '时间轴',
                    style: TextStyle(fontSize: AppTypography.caption),
                  ),
                ),
            ],
          ),
        ),
      );

  Widget _unplacedBlock(List<RouteMapUnplaced> unplaced) => DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.ground,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.content),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${unplaced.length} 个安排未在地图上打点',
                style: const TextStyle(
                  fontSize: AppTypography.caption,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              for (final RouteMapUnplaced entry in unplaced)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    '${entry.title}：${entry.reason}',
                    style: const TextStyle(
                      fontSize: AppTypography.caption,
                      color: AppColors.crackle,
                      height: 1.45,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );

  /// 地图不可用时的兜底：把当天的安排按时间排成文字路线。
  ///
  /// 用的是方案自己已经带回来的数据，因此即使完全没有网络，
  /// 用户看到的也不是一块空白，而是一份仍然可读的路线。
  Widget _fallbackRoute() {
    final PlanDay? day = _dayIndex < widget.days.length ? widget.days[_dayIndex] : null;
    final List<PlanStop> stops = day?.stops ?? const <PlanStop>[];
    final String reason = _failure?.message ??
        _snapshot?.message ??
        (widget.planId == null || widget.planId!.isEmpty
            ? '这份方案是本地演示数据，没有对应的服务端行程，因此无法取底图。'
            : '地图服务暂时不可用。');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.ground,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.content),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(Icons.route_outlined, size: 16, color: AppColors.celadonDeep),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    reason,
                    style: const TextStyle(
                      fontSize: AppTypography.caption,
                      color: AppColors.inkSoft,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
            if (stops.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              const Text(
                '当天文字路线',
                style: TextStyle(
                  fontSize: AppTypography.caption,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              for (final PlanStop stop in stops)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    <String>[
                      if (stop.time.isNotEmpty) stop.time,
                      stop.title,
                      if (stop.transport != null && stop.transport!.isNotEmpty) stop.transport!,
                    ].join(' · '),
                    style: const TextStyle(
                      fontSize: AppTypography.secondary,
                      color: AppColors.inkSoft,
                      height: 1.5,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 折线画笔：先画一层白色描边再画主色，避免路线落在深色路网上时看不清。
class _RoutePainter extends CustomPainter {
  const _RoutePainter({required this.points, required this.color});

  final List<Offset> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) {
      return;
    }
    final Path path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final Offset point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    final Paint casing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white.withValues(alpha: 0.85);
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    canvas.drawPath(path, casing);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(_RoutePainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.color != color;
}
