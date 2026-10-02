import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../app/providers.dart';
import '../core/network/api_failure.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/widgets/app_back_button.dart';
import '../core/widgets/photo_plate.dart';
import '../core/widgets/surface_card.dart';
import '../core/widgets/tag_pill.dart';
import '../models/trip_models.dart';
import '../data/repositories/community_repository.dart';
import '../data/repositories/travel_repository.dart';

/// Turns one saved trip into a public travel note.
///
/// The screen deliberately keeps the trip association visible at all times:
/// the community is a record of a real journey, not a free-form post wall.
class CommunityPublishScreen extends ConsumerStatefulWidget {
  const CommunityPublishScreen({super.key});

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
  int _uploading = 0;
  int _uploadTotal = 0;
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
        _selectedTrip = _trips.isEmpty ? null : _trips.first;
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
    if (_uploading > 0 || _imageUrls.length >= _maxImages) return;
    try {
      final List<XFile> picked = await _picker.pickMultiImage(imageQuality: 85);
      if (picked.isEmpty) return;
      final int remaining = _maxImages - _imageUrls.length;
      final List<XFile> selected = picked.take(remaining).toList();
      if (mounted) {
        setState(() {
          _uploadTotal = selected.length;
          _uploading = 0;
          _error = null;
        });
      }
      for (final XFile image in selected) {
        try {
          final String url =
              await _communityRepository.uploadImage(File(image.path));
          if (url.isEmpty) continue;
          if (mounted) {
            setState(() {
              _imageUrls.add(url);
              _uploading++;
            });
          }
        } on ApiFailure catch (failure) {
          if (mounted) setState(() => _error = failure.message);
        }
      }
      if (mounted) setState(() => _uploading = _uploadTotal);
    } on Object {
      if (mounted) setState(() => _error = '图片选择失败，请检查系统权限。');
    }
  }

  void _removeImage(String url) {
    setState(() => _imageUrls.remove(url));
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (_selectedTrip == null) {
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
      await _communityRepository.createPost(
        title: _title.text.trim(),
        content: _content.text.trim(),
        city: _city.text.trim(),
        tags: _tags.text.trim(),
        visibility: _visibility,
        tripPlanId: _selectedTrip!.id,
        imageUrls: _imageUrls,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('已提交审核'),
          content: const Text(
            '旅记已进入待审核队列。审核通过后才会出现在公开旅记中；你可以稍后在评论区看到状态。',
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
        title: const Text('写旅记'),
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
            onChanged: (TripSummary? trip) => setState(() => _selectedTrip = trip),
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
            uploading: _uploading,
            uploadTotal: _uploadTotal,
            onAdd: _pickImages,
            onRemove: _removeImage,
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
            onPressed: _submitting || _uploading > 0 ? null : _submit,
            icon: const Icon(Icons.send_outlined, size: 18),
            label: Text(
              _submitting
                  ? '提交中…'
                  : _uploading > 0
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
          DropdownButtonFormField<String>(
            initialValue: selected?.id,
            isExpanded: true,
            decoration: const InputDecoration(
              hintText: '选择一份本人行程',
            ),
            items: trips
                .map(
                  (TripSummary trip) => DropdownMenuItem<String>(
                    value: trip.id,
                    child: Text(
                      '${trip.title}  ·  ${trip.daysCount}天',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (String? id) {
              if (id == null) return;
              onChanged(trips.firstWhere((trip) => trip.id == id));
            },
          ),
          if (selected != null) ...<Widget>[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                TagPill(selected!.corridor, dense: true),
                TagPill('${selected!.daysCount} 天', dense: true),
                TagPill(selected!.intensity, dense: true),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ImageEditor extends StatelessWidget {
  const _ImageEditor({
    required this.urls,
    required this.uploading,
    required this.uploadTotal,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> urls;
  final int uploading;
  final int uploadTotal;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const _FieldLabel('旅记图片'),
                const Spacer(),
                Text(
                  '${urls.length}/9',
                  style: const TextStyle(
                    fontSize: AppTypography.caption,
                    color: AppColors.crackle,
                    fontFeatures: AppTypography.tabularFigures,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 92,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: <Widget>[
                  for (final String url in urls)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Stack(
                        children: <Widget>[
                          PhotoPlate(
                            url: url,
                            width: 92,
                            height: 92,
                            radius: AppSpacing.radiusSmall,
                            fallbackLabel: '图片',
                          ),
                          Positioned(
                            right: 3,
                            top: 3,
                            child: InkResponse(
                              onTap: () => onRemove(url),
                              radius: 15,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(
                                  color: Color(0xB316211F),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (urls.length < 9)
                    InkWell(
                      onTap: onAdd,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                      child: Container(
                        width: 92,
                        height: 92,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceTint,
                          border: Border.all(color: AppColors.hairline),
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusSmall),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Icon(Icons.add_photo_alternate_outlined,
                                color: AppColors.celadonDeep),
                            SizedBox(height: 5),
                            Text(
                              '添加图片',
                              style: TextStyle(
                                fontSize: AppTypography.caption,
                                color: AppColors.celadonDeep,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (uploading > 0) ...<Widget>[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: uploadTotal <= 0 ? null : uploading / uploadTotal,
              ),
              const SizedBox(height: 5),
              Text(
                '正在上传第 $uploading / $uploadTotal 张图片…',
                style: const TextStyle(
                  fontSize: AppTypography.caption,
                  color: AppColors.crackle,
                ),
              ),
            ],
          ],
        ),
      );
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
