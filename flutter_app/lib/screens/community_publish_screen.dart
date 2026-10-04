import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../app/providers.dart';
import '../core/icons/app_icons.dart';
import '../core/network/api_failure.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/widgets/app_back_button.dart';
import '../core/widgets/form_controls.dart';
import '../core/widgets/option_sheet.dart';
import '../core/widgets/photo_plate.dart';
import '../core/widgets/press_scale.dart';
import '../core/widgets/surface_card.dart';
import '../models/community_models.dart';
import '../models/trip_models.dart';
import '../data/repositories/community_repository.dart';
import '../data/repositories/travel_repository.dart';

/// Turns one saved trip into a public travel note.
///
/// The screen deliberately keeps the trip association visible at all times:
/// the community is a record of a real journey, not a free-form post wall.
class CommunityPublishScreen extends ConsumerStatefulWidget {
  const CommunityPublishScreen({super.key, this.editing});

  /// 传入要修改的旅记就是编辑模式；为空则是新建。
  final CommunityPost? editing;

  @override
  ConsumerState<CommunityPublishScreen> createState() =>
      _CommunityPublishScreenState();
}

class _CommunityPublishScreenState
    extends ConsumerState<CommunityPublishScreen> {
  static const int _maxImages = 9;

  final ImagePicker _picker = ImagePicker();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _content = TextEditingController();
  final TextEditingController _city = TextEditingController();
  final TextEditingController _tags = TextEditingController();

  List<TripSummary> _trips = <TripSummary>[];
  TripSummary? _selectedTrip;
  final List<String> _imageUrls = <String>[];

  /// 上传中是一个明确的是/否状态；进度单独计数，避免"永不归零"的布尔漂移。
  bool _uploading = false;
  int _uploadProcessed = 0;
  int _uploadTotal = 0;

  /// 上传失败的图片连同原文件一起留在编辑页里，用户点那一张就能重试。
  final List<_FailedUpload> _failedUploads = <_FailedUpload>[];
  bool _loadingTrips = true;
  bool _submitting = false;
  String _visibility = 'PUBLIC';
  String? _error;

  TravelRepository get _travelRepository => ref.read(travelRepositoryProvider);
  CommunityRepository get _communityRepository =>
      ref.read(communityRepositoryProvider);

  @override
  void initState() {
    super.initState();
    final CommunityPost? editing = widget.editing;
    if (editing != null) {
      _title.text = editing.title;
      _content.text = editing.content;
      _city.text = editing.city;
      _tags.text = editing.tags.join(',');
      _visibility = editing.visibility == 'PRIVATE' ? 'PRIVATE' : 'PUBLIC';
      // 读回来的是可直接显示的绝对地址，入库前还原成相对路径，
      // 否则会把某台设备的 IP 写进数据库。
      _imageUrls.addAll(
        editing.imageUrls.map(CommunityRepository.storageImageUrl),
      );
    }
    _loadTrips();
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _city.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _loadTrips() async {
    setState(() {
      _loadingTrips = true;
      _error = null;
    });
    try {
      final TripListResult result = await _travelRepository.fetchTripPlans();
      if (!mounted) return;
      setState(() {
        _trips = result.items.where((trip) => trip.id.isNotEmpty).toList();
        final String? wanted = widget.editing?.tripPlanId;
        if (wanted == null) {
          _selectedTrip = _trips.isEmpty ? null : _trips.first;
        } else {
          TripSummary? match;
          for (final TripSummary trip in _trips) {
            if (trip.id == wanted) {
              match = trip;
            }
          }
          _selectedTrip = match;
        }
        _loadingTrips = false;
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loadingTrips = false;
        _error = failure.message;
      });
    }
  }

  Future<void> _pickImages() async {
    // 失败的图片仍然占着名额：否则用户可以连着挑 9 张、再挑 9 张，
    // 最后摆出一屏 18 张谁也没见过的图。
    final int used = _imageUrls.length + _failedUploads.length;
    if (_uploading || used >= _maxImages) return;

    final List<XFile> picked;
    try {
      picked = await _picker.pickMultiImage(imageQuality: 85);
    } on Object {
      if (mounted) setState(() => _error = '无法打开相册，请检查系统权限。');
      return;
    }
    if (picked.isEmpty || !mounted) return;

    final int remaining = _maxImages - used;
    final List<XFile> selected = picked.take(remaining).toList();
    setState(() {
      _error = null;
      _uploading = true;
      _uploadProcessed = 0;
      _uploadTotal = selected.length;
    });

    try {
      for (final XFile image in selected) {
        try {
          final String url =
              await _communityRepository.uploadImage(File(image.path));
          if (url.isEmpty) {
            if (mounted) {
              setState(() => _failedUploads.add(
                    _FailedUpload(file: image, message: '服务端没有返回图片地址'),
                  ));
            }
            continue;
          }
          if (mounted) {
            setState(() => _imageUrls.add(url));
          }
        } on ApiFailure catch (failure) {
          if (mounted) {
            setState(() => _failedUploads.add(
                  _FailedUpload(file: image, message: failure.message),
                ));
          }
        } on Object {
          if (mounted) {
            setState(() => _failedUploads.add(
                  _FailedUpload(file: image, message: '上传失败'),
                ));
          }
        } finally {
          // 成功和失败都要推进进度，否则进度条会停在中途。
          if (mounted) setState(() => _uploadProcessed++);
        }
      }
    } finally {
      // "上传中"的唯一出口：任何异常都不会把页面锁在加载态。
      if (mounted) {
        setState(() {
          _uploading = false;
          _error = _failedUploadFeedback;
        });
      }
    }
  }

  /// 上传失败时给用户的一句汇总。具体原因挂在每一张图上。
  String? get _failedUploadFeedback {
    final int count = _failedUploads.length;
    if (count == 0) {
      return null;
    }
    return count == 1
        ? '有 1 张图片没有上传成功，点图片上的「重试」即可，其他图片已经保存。'
        : '有 $count 张图片没有上传成功，逐张点「重试」即可，其他图片已经保存。';
  }

  /// 只重传一张失败的图片 —— 这是"上传失败"的正确粒度。
  Future<void> _retryUpload(_FailedUpload entry) async {
    if (entry.retrying || _uploading) {
      return;
    }
    setState(() {
      entry.retrying = true;
      _error = null;
    });
    try {
      final String url =
          await _communityRepository.uploadImage(File(entry.file.path));
      if (!mounted) return;
      setState(() {
        if (url.isEmpty) {
          entry.message = '服务端没有返回图片地址';
        } else {
          _failedUploads.remove(entry);
          _imageUrls.add(url);
        }
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() => entry.message = failure.message);
    } on Object {
      if (!mounted) return;
      setState(() => entry.message = '上传失败');
    } finally {
      if (mounted) {
        setState(() {
          entry.retrying = false;
          _error = _failedUploadFeedback;
        });
      }
    }
  }

  void _discardFailedUpload(_FailedUpload entry) {
    setState(() {
      _failedUploads.remove(entry);
      _error = _failedUploadFeedback;
    });
  }

  void _removeImage(String url) {
    setState(() => _imageUrls.remove(url));
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    final CommunityPost? editing = widget.editing;
    final String? tripId = _selectedTrip?.id ?? editing?.tripPlanId;
    if (tripId == null) {
      setState(() => _error = '请选择一份本人已保存的行程。');
      return;
    }
    if (_title.text.trim().isEmpty || _content.text.trim().isEmpty) {
      setState(() => _error = '标题和正文不能为空。');
      return;
    }
    if (_city.text.trim().isEmpty) {
      setState(() => _error = '请填写旅记所在城市。');
      return;
    }
    setState(() => _submitting = true);
    try {
      final List<String> storedImages =
          _imageUrls.map(CommunityRepository.storageImageUrl).toList();
      if (editing == null) {
        await _communityRepository.createPost(
          title: _title.text.trim(),
          content: _content.text.trim(),
          city: _city.text.trim(),
          tags: _tags.text.trim(),
          visibility: _visibility,
          tripPlanId: tripId,
          imageUrls: storedImages,
        );
      } else {
        await _communityRepository.updatePost(
          id: editing.id,
          title: _title.text.trim(),
          content: _content.text.trim(),
          city: _city.text.trim(),
          tags: _tags.text.trim(),
          visibility: _visibility,
          tripPlanId: tripId,
          imageUrls: storedImages,
        );
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: Text(editing == null ? '已提交审核' : '修改已提交审核'),
          content: Text(
            editing == null
                ? '旅记已进入待审核队列。审核通过后才会出现在公开旅记中；你可以在「我的旅记」查看状态。'
                : '修改已进入待审核队列，审核通过后公开内容会更新；你可以在「我的旅记」查看状态。',
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = failure.message;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = '提交失败，请稍后重试。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final double page = AppSpacing.pageFor(MediaQuery.sizeOf(context).width);
    return Scaffold(
      backgroundColor: AppColors.ground,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(widget.editing == null ? '写旅记' : '编辑旅记'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(page, 8, page, 28),
        children: <Widget>[
          const Text(
            '把一份行程，整理成一段可以分享的旅行时光。',
            style: TextStyle(
              fontSize: AppTypography.lead,
              color: AppColors.inkSoft,
              height: 1.55,
            ),
          ),
          const SizedBox(height: AppSpacing.section),
          _TripSelector(
            loading: _loadingTrips,
            trips: _trips,
            selected: _selectedTrip,
            onChanged: (TripSummary? trip) =>
                setState(() => _selectedTrip = trip),
            onRetry: _loadTrips,
          ),
          const SizedBox(height: AppSpacing.content),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _FieldLabel('标题'),
                TextField(
                  controller: _title,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    hintText: '例如：洛阳两日，沿着伊河看石窟',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 16),
                const _FieldLabel('正文'),
                TextField(
                  controller: _content,
                  maxLength: 3000,
                  minLines: 5,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    hintText: '写下路线、感受和给下一位旅人的建议。',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const _FieldLabel('城市'),
                          TextField(
                            controller: _city,
                            maxLength: 80,
                            decoration: const InputDecoration(
                              hintText: '洛阳',
                              counterText: '',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const _FieldLabel('主题标签'),
                          TextField(
                            controller: _tags,
                            maxLength: 200,
                            decoration: const InputDecoration(
                              hintText: '历史文化,博物馆',
                              counterText: '',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.content),
          _ImageEditor(
            urls: _imageUrls,
            failed: _failedUploads,
            displayUrl: _communityRepository.mediaUrl,
            uploading: _uploading,
            uploadProcessed: _uploadProcessed,
            uploadTotal: _uploadTotal,
            onAdd: _pickImages,
            onRemove: _removeImage,
            onRetry: _retryUpload,
            onDiscard: _discardFailedUpload,
          ),
          const SizedBox(height: AppSpacing.content),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _FieldLabel('公开范围'),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  segments: const <ButtonSegment<String>>[
                    ButtonSegment<String>(
                      value: 'PUBLIC',
                      icon: Icon(Icons.public, size: 17),
                      label: Text('公开'),
                    ),
                    ButtonSegment<String>(
                      value: 'PRIVATE',
                      icon: Icon(Icons.lock_outline, size: 17),
                      label: Text('仅自己'),
                    ),
                  ],
                  selected: <String>{_visibility},
                  onSelectionChanged: (Set<String> value) =>
                      setState(() => _visibility = value.first),
                ),
                const SizedBox(height: 10),
                const Text(
                  '图片会在服务端重新编码并去除 EXIF 位置信息；提交后先进入审核，不会直接公开。',
                  style: TextStyle(
                    fontSize: AppTypography.caption,
                    color: AppColors.crackle,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 14),
            Text(
              _error!,
              style: const TextStyle(
                fontSize: AppTypography.caption,
                color: AppColors.riskText,
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _submitting || _uploading ? null : _submit,
            icon: const Icon(Icons.send_outlined, size: 18),
            label: Text(
              _submitting
                  ? '提交中…'
                  : _uploading
                      ? '图片上传中…'
                      : '提交审核',
            ),
          ),
        ],
      ),
    );
  }
}

class _TripSelector extends StatelessWidget {
  const _TripSelector({
    required this.loading,
    required this.trips,
    required this.selected,
    required this.onChanged,
    required this.onRetry,
  });

  final bool loading;
  final List<TripSummary> trips;
  final TripSummary? selected;
  final ValueChanged<TripSummary?> onChanged;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SurfaceCard(
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (trips.isEmpty) {
      return SurfaceCard(
        color: AppColors.cautionSurface,
        shadow: const <BoxShadow>[],
        child: Row(
          children: <Widget>[
            const Icon(Icons.route_outlined, color: AppColors.cautionText),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                '还没有可关联的已保存行程。请先完成并保存一份行程。',
                style: TextStyle(
                  fontSize: AppTypography.caption,
                  color: AppColors.cautionText,
                  height: 1.5,
                ),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      );
    }
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _FieldLabel('关联行程'),
          const SizedBox(height: 8),
          _TripField(trip: selected, onTap: () => _pick(context)),
        ],
      ),
    );
  }

  /// 用主题化弹层选行程，而不是 Material 下拉框。
  ///
  /// 下拉框展开后是一块没有主题的白色矩形列表，和收起态像两个产品；
  /// 这里复用交通方式那套 `OptionTile`，收起态、展开态、选中态是同一套语言。
  Future<void> _pick(BuildContext context) async {
    final TripSummary? picked = await showModalBottomSheet<TripSummary>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.8,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SheetHandle(),
                const SizedBox(height: 16),
                const Text(
                  '选择关联行程',
                  style: TextStyle(
                    fontSize: AppTypography.sectionTitle,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '旅记会带上这份行程的路线与天数，读者更容易判断方案可不可行。',
                  style: TextStyle(
                    fontSize: AppTypography.caption,
                    color: AppColors.crackle,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 14),
                for (int index = 0; index < trips.length; index++) ...<Widget>[
                  OptionTile(
                    label: trips[index].title,
                    detail: '${trips[index].corridor} · '
                        '${trips[index].daysCount} 天 · ${trips[index].intensity}',
                    selected: trips[index].id == selected?.id,
                    onTap: () => Navigator.of(sheetContext).pop(trips[index]),
                  ),
                  if (index != trips.length - 1) const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    if (picked != null) onChanged(picked);
  }
}

/// 关联行程的收起态：和展开后的选项用同一套圆角、描边与颜色。
class _TripField extends StatelessWidget {
  const _TripField({required this.trip, required this.onTap});

  final TripSummary? trip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(AppSpacing.radiusControl);
    final TripSummary? current = trip;
    return Semantics(
      button: true,
      label: current == null ? '选择关联行程' : '关联行程：${current.title}',
      child: Material(
        color: AppColors.surfaceTint,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: AppColors.celadonPale),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.route_outlined,
                      size: 20, color: AppColors.celadonDeep),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          current?.title ?? '选择一份本人行程',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: AppTypography.body,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          current == null
                              ? '旅记需要关联一段真实走过的行程'
                              : '${current.corridor} · ${current.daysCount} 天 · ${current.intensity}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: AppTypography.caption,
                            color: AppColors.crackle,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.unfold_more,
                      size: 18, color: AppColors.celadonDeep),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 图片文件名压缩到一行里放得下。只用于提示，不参与任何判断。
String _shortName(String value) =>
    value.length <= 16 ? value : '${value.substring(0, 16)}…';

/// 一张上传失败、但还留在编辑页里的图片。
///
/// 失败时必须连着原始文件一起留住：只记一个文件名，用户就只能重新翻一遍
/// 相册再传一次，而"重选全部"正是这一版要消掉的行为。
class _FailedUpload {
  _FailedUpload({required this.file, required this.message});

  final XFile file;
  String message;
  bool retrying = false;
}

class _ImageEditor extends StatelessWidget {
  const _ImageEditor({
    required this.urls,
    required this.failed,
    required this.displayUrl,
    required this.uploading,
    required this.uploadProcessed,
    required this.uploadTotal,
    required this.onAdd,
    required this.onRemove,
    required this.onRetry,
    required this.onDiscard,
  });

  static const int _maxImages = 9;

  final List<String> urls;

  /// 上传失败、等待重试的图片，顺序与用户挑选的顺序一致。
  final List<_FailedUpload> failed;

  /// 入库值 -> 本机可显示的绝对地址。移除回调仍然回传入库值。
  final String Function(String) displayUrl;
  final bool uploading;
  final int uploadProcessed;
  final int uploadTotal;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;
  final ValueChanged<_FailedUpload> onRetry;
  final ValueChanged<_FailedUpload> onDiscard;

  @override
  Widget build(BuildContext context) {
    // 失败的图片也算占位：它们随时可能变成一张真的图片。
    final int used = urls.length + failed.length;
    final int remaining = _maxImages - used;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const _FieldLabel('旅记图片'),
              const SizedBox(width: 8),
              Text(
                used == 0 ? '最多 $_maxImages 张' : '已上传 ${urls.length} 张',
                style: const TextStyle(
                  fontSize: AppTypography.caption,
                  color: AppColors.crackle,
                  fontFeatures: AppTypography.tabularFigures,
                ),
              ),
              const Spacer(),
              if (!uploading && remaining > 0)
                Text(
                  '还可添加 $remaining 张',
                  style: const TextStyle(
                    fontSize: AppTypography.caption,
                    color: AppColors.crackle,
                  ),
                ),
            ],
          ),
          if (failed.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(
                  Icons.error_outline,
                  size: 15,
                  color: AppColors.kilnRed,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '有 ${failed.length} 张没有传上去。点图片上的「重试」只重传那一张，'
                    '已经成功的不会重来一遍。',
                    style: const TextStyle(
                      fontSize: AppTypography.caption,
                      color: AppColors.riskText,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            height: 100,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: <Widget>[
                for (final String url in urls)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: _Thumbnail(
                      url: displayUrl(url),
                      onRemove: () => onRemove(url),
                    ),
                  ),
                for (final _FailedUpload entry in failed)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: _FailedTile(
                      entry: entry,
                      onRetry: () => onRetry(entry),
                      onDiscard: () => onDiscard(entry),
                    ),
                  ),
                if (remaining > 0)
                  _AddTile(
                    remaining: remaining,
                    onTap: uploading ? null : onAdd,
                  ),
              ],
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: uploading
                ? Padding(
                    key: const ValueKey<String>('uploading'),
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        ClipRRect(
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusPill),
                          child: LinearProgressIndicator(
                            minHeight: 6,
                            value: uploadTotal <= 0
                                ? null
                                : uploadProcessed / uploadTotal,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '正在上传 $uploadProcessed / $uploadTotal 张图片，请稍候…',
                          style: const TextStyle(
                            fontSize: AppTypography.caption,
                            color: AppColors.crackle,
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey<String>('idle')),
          ),
        ],
      ),
    );
  }
}

/// 上传失败的那一张：本地缩略图 + 单张重试。
///
/// 用本地文件当预览，是因为这一张从来没上传成功过 —— 服务器上根本没有它，
/// 拿一个网络地址去渲染只会得到一个假的占位图。
class _FailedTile extends StatelessWidget {
  const _FailedTile({
    required this.entry,
    required this.onRetry,
    required this.onDiscard,
  });

  final _FailedUpload entry;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(AppSpacing.radiusControl);
    return Tooltip(
      message: '${_shortName(entry.file.name)}：${entry.message}',
      child: Semantics(
        label: '上传失败：${entry.message}',
        child: SizedBox(
          width: 100,
          height: 100,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: radius,
                  child: Image.file(
                    File(entry.file.path),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const ColoredBox(
                      color: AppColors.surfaceSunken,
                      child: Center(
                        child: Icon(
                          Icons.image_not_supported_outlined,
                          size: 22,
                          color: AppColors.crackle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // 压一层暗红：一眼就能把"没传上去的"和"已经好了的"分开。
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0x59B23A22),
                    borderRadius: radius,
                    border: Border.all(color: AppColors.kilnRed, width: 1.5),
                  ),
                ),
              ),
              Positioned(
                right: 4,
                top: 4,
                child: Tooltip(
                  message: '不再上传这张图片',
                  child: InkResponse(
                    onTap: onDiscard,
                    radius: 16,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.ink,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.surface, width: 2),
                      ),
                      child: const Icon(
                        Icons.close,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              if (entry.retrying)
                const Positioned.fill(
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    ),
                  ),
                )
              else
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: _RetryChip(onTap: onRetry),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「重试」按钮：只重传它所在的这一张。
class _RetryChip extends StatelessWidget {
  const _RetryChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(Icons.refresh, size: 13, color: AppColors.kilnRed),
                SizedBox(width: 3),
                Flexible(
                  child: Text(
                    '重试',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.kilnRed,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// 已选图片的缩略图。移除按钮常驻但不抢眼：它是可点操作，不是装饰。
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.url, required this.onRemove});

  final String url;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Stack(
        children: <Widget>[
          PhotoPlate(
            url: url,
            width: 100,
            height: 100,
            radius: AppSpacing.radiusControl,
            fallbackLabel: '旅记图片',
          ),
          Positioned(
            right: 4,
            top: 4,
            child: Tooltip(
              message: '移除这张图片',
              child: InkResponse(
                onTap: onRemove,
                radius: 16,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.ink,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.surface, width: 2),
                  ),
                  child: const Icon(Icons.close, size: 12, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      );
}

/// 添加图片的入口。上传中置灰并说明原因，不做点不动的假按钮。
class _AddTile extends StatelessWidget {
  const _AddTile({required this.remaining, required this.onTap});

  final int remaining;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(AppSpacing.radiusControl);
    return Tooltip(
      message: onTap == null ? '正在上传，请稍候' : '从相册添加图片',
      child: PressScale(
        child: SizedBox(
          width: 100,
          height: 100,
          child: Material(
            color: AppColors.surfaceTint,
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(
                    color: onTap == null
                        ? AppColors.hairline
                        : AppColors.celadonPale,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    AppIcon(
                      AppIcons.upload,
                      size: 22,
                      color: onTap == null
                          ? AppColors.crackle
                          : AppColors.celadonDeep,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '添加图片',
                      style: TextStyle(
                        fontSize: AppTypography.caption,
                        fontWeight: FontWeight.w600,
                        color: onTap == null
                            ? AppColors.crackle
                            : AppColors.celadonDeep,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '还可 $remaining 张',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.crackle,
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

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: AppTypography.secondary,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
        ),
      );
}
