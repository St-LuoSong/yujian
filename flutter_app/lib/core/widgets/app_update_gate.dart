import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/session_providers.dart';
import '../../data/repositories/app_update_repository.dart';
import '../../models/app_update_models.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'surface_card.dart';

/// Checks the trusted server release channel without holding normal startup hostage.
class AppUpdateGate extends ConsumerStatefulWidget {
  const AppUpdateGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends ConsumerState<AppUpdateGate>
    with WidgetsBindingObserver {
  static const Duration _foregroundInterval = Duration(hours: 6);

  AppUpdateInfo? _update;
  DateTime? _checkedAt;
  bool _checking = false;
  bool _dismissed = false;
  bool _opening = false;
  String? _actionError;

  AppUpdateRepository get _repository => ref.read(appUpdateRepositoryProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final DateTime? checked = _checkedAt;
    if (checked == null || DateTime.now().difference(checked) >= _foregroundInterval) {
      _check();
    }
  }

  Future<void> _check() async {
    if (_checking) return;
    if (mounted) setState(() => _checking = true);
    try {
      final AppUpdateInfo result = await _repository.check();
      if (!mounted) return;
      setState(() {
        _checkedAt = DateTime.now();
        _update = result.updateAvailable ? result : null;
        _dismissed = false;
        _actionError = null;
      });
      // 版本回执只在登录后发：服务端要把它写进某个人的消息中心。
      if (ref.read(sessionProvider).valueOrNull != null) {
        await _repository.acknowledge();
      }
    } on Object {
      // Version checks are advisory unless a known required release is already
      // on screen. A transient network failure must not break normal travel use.
      if (mounted) setState(() => _checkedAt = DateTime.now());
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _download() async {
    final AppUpdateInfo? update = _update;
    if (update == null || _opening) return;
    setState(() {
      _opening = true;
      _actionError = null;
    });
    try {
      final bool opened = await _repository.openDownload(update);
      if (!mounted) return;
      setState(() {
        _opening = false;
        _actionError = opened ? null : '没有找到可用的下载应用，请稍后重试。';
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _opening = false;
        _actionError = '无法打开下载地址，请检查网络后重试。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 登录之后再补一次回执：先装包后登录和先登录后升级是两条路径，
    // 两条都该在消息中心留下这次更新的说明。
    ref.listen(sessionProvider, (previous, next) {
      if (previous?.valueOrNull == null && next.valueOrNull != null) {
        _repository.acknowledge();
      }
    });

    final AppUpdateInfo? update = _update;
    if (update?.updateRequired == true) {
      return _RequiredUpdatePage(
        update: update!,
        checking: _checking,
        opening: _opening,
        error: _actionError,
        onDownload: _download,
        onRetry: _check,
      );
    }

    return Stack(
      children: <Widget>[
        widget.child,
        if (update != null && !_dismissed)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              minimum: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: _OptionalUpdateCard(
                update: update,
                opening: _opening,
                error: _actionError,
                onDownload: _download,
                onDismiss: () => setState(() => _dismissed = true),
              ),
            ),
          ),
      ],
    );
  }
}

class _OptionalUpdateCard extends StatelessWidget {
  const _OptionalUpdateCard({
    required this.update,
    required this.opening,
    required this.error,
    required this.onDownload,
    required this.onDismiss,
  });

  final AppUpdateInfo update;
  final bool opening;
  final String? error;
  final VoidCallback onDownload;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: SurfaceCard(
          color: AppColors.ink,
          shadow: const <BoxShadow>[
            BoxShadow(color: Color(0x42101D19), blurRadius: 28, offset: Offset(0, 10)),
          ],
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.celadon,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
                ),
                child: const Icon(Icons.system_update_alt, color: Colors.white, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      update.signatureMismatch
                          ? '安装包签名需要校验'
                          : (update.releaseTitle.isEmpty ? '新版本已经准备好' : update.releaseTitle),
                      style: const TextStyle(
                        color: AppColors.onInk,
                        fontSize: AppTypography.cardTitle,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'v${update.latestVersionName} · ${_size(update.fileSize)}',
                      style: const TextStyle(color: AppColors.onInkMuted, fontSize: AppTypography.caption),
                    ),
                    if (error != null) ...<Widget>[
                      const SizedBox(height: 5),
                      Text(error!, style: const TextStyle(color: Color(0xFFFFB8A8), fontSize: 11)),
                    ],
                    const SizedBox(height: 9),
                    Row(
                      children: <Widget>[
                        TextButton(onPressed: onDismiss, child: const Text('稍后提醒')),
                        const SizedBox(width: 4),
                        FilledButton(
                          onPressed: opening ? null : onDownload,
                          child: Text(opening ? '正在打开…' : '立即更新'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _RequiredUpdatePage extends StatelessWidget {
  const _RequiredUpdatePage({
    required this.update,
    required this.checking,
    required this.opening,
    required this.error,
    required this.onDownload,
    required this.onRetry,
  });

  final AppUpdateInfo update;
  final bool checking;
  final bool opening;
  final String? error;
  final VoidCallback onDownload;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.ground,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  children: <Widget>[
                    Container(
                      width: 76,
                      height: 76,
                      decoration: const BoxDecoration(color: AppColors.celadonDeep, shape: BoxShape.circle),
                      child: const Icon(Icons.shield_outlined, color: AppColors.onInk, size: 34),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      '请更新后继续使用',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.ink),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      update.signatureMismatch ? '当前安装包签名与官方发布证书不一致' : update.releaseTitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: AppTypography.lead, color: AppColors.inkSoft),
                    ),
                    const SizedBox(height: 18),
                    SurfaceCard(
                      color: AppColors.surfaceTint,
                      shadow: const <BoxShadow>[],
                      child: Text(
                        update.signatureMismatch
                            ? '为保障账号与行程数据安全，请从官方发布地址重新下载安装。Android 安装器会再次校验签名；如无法覆盖安装，请先备份需要保留的数据。'
                            : update.releaseNotes,
                        style: const TextStyle(fontSize: AppTypography.body, height: 1.75, color: AppColors.inkSoft),
                      ),
                    ),
                    if (error != null) ...<Widget>[
                      const SizedBox(height: 12),
                      Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.riskText)),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: opening ? null : onDownload,
                        icon: const Icon(Icons.download_outlined),
                        label: Text(opening ? '正在打开下载…' : '下载 v${update.latestVersionName}'),
                      ),
                    ),
                    TextButton(onPressed: checking ? null : onRetry, child: Text(checking ? '正在重新检查…' : '我已安装，重新检查')),
                    Text(
                      '安装时 Android 会再次校验新旧应用签名是否一致。',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: AppTypography.caption, color: AppColors.crackle),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

String _size(int bytes) {
  if (bytes <= 0) return '大小未知';
  if (bytes >= 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(bytes / 1024).ceil()} KB';
}
