import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/network/api_failure.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/widgets/app_back_button.dart';
import '../core/widgets/surface_card.dart';
import '../models/app_update_models.dart';

/// 手动检查更新。
///
/// 与启动时的自动检查走同一套接口、同一份判定（含"落后太多就强制更新"），
/// 区别只在于这一次是用户主动点的，所以结果要当场讲清楚：当前版本是哪个、
/// 最新版本是哪个、有没有更新、要不要强制 —— 而不是丢一句"已是最新"。
class CheckUpdateScreen extends ConsumerStatefulWidget {
  const CheckUpdateScreen({super.key});

  @override
  ConsumerState<CheckUpdateScreen> createState() => _CheckUpdateScreenState();
}

class _CheckUpdateScreenState extends ConsumerState<CheckUpdateScreen> {
  InstalledAppInfo? _installed;
  AppUpdateInfo? _update;
  bool _checking = true;
  bool _opening = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final InstalledAppInfo installed =
          await ref.read(appReleasePlatformProvider).installedInfo();
      final AppUpdateInfo update =
          await ref.read(appUpdateRepositoryProvider).check();
      if (!mounted) return;
      setState(() {
        _installed = installed;
        _update = update;
        _checking = false;
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = failure.message;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = '检查更新失败，请检查网络后重试。';
      });
    }
  }

  Future<void> _download() async {
    final AppUpdateInfo? update = _update;
    if (update == null || _opening) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final bool opened =
          await ref.read(appUpdateRepositoryProvider).openDownload(update);
      if (!mounted) return;
      setState(() {
        _opening = false;
        if (!opened) {
          _error = '没有找到可用的下载应用，请稍后重试。';
        }
      });
      if (opened) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('已打开下载页面，装完后回到这里即可。')),
          );
      }
    } on Object {
      if (!mounted) return;
      setState(() {
        _opening = false;
        _error = '无法打开下载地址，请检查网络后重试。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final double page = AppSpacing.pageFor(MediaQuery.sizeOf(context).width);
    final InstalledAppInfo? installed = _installed;
    final AppUpdateInfo? update = _update;
    final bool available = update?.updateAvailable == true;
    final bool required = update?.updateRequired == true;

    return Scaffold(
      backgroundColor: AppColors.ground,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('检查更新'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(page, 8, page, 36),
        children: <Widget>[
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _VersionRow(
                  label: '当前版本',
                  value: installed == null
                      ? '读取中…'
                      : 'v${installed.versionName}（${installed.versionCode}）',
                ),
                const Divider(height: 22),
                _VersionRow(
                  label: '最新版本',
                  value: _checking
                      ? '检查中…'
                      : (update == null || !update.releaseAvailable
                          ? '服务端暂未发布'
                          : 'v${update.latestVersionName}（${update.latestVersionCode}）'),
                ),
                const Divider(height: 22),
                _VersionRow(
                  label: '状态',
                  value: _statusText(update, required, available),
                  tone: required
                      ? AppColors.kilnRed
                      : (available ? AppColors.celadonDeep : AppColors.ink),
                ),
              ],
            ),
          ),
          if (available) ...<Widget>[
            const SizedBox(height: AppSpacing.content),
            SurfaceCard(
              color: required ? AppColors.riskSurface : AppColors.surfaceTint,
              shadow: const <BoxShadow>[],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    update!.releaseTitle.isEmpty
                        ? '发现新版本'
                        : update.releaseTitle,
                    style: TextStyle(
                      fontSize: AppTypography.cardTitle,
                      fontWeight: FontWeight.w700,
                      color: required ? AppColors.riskText : AppColors.ink,
                    ),
                  ),
                  if (required) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      _requiredReason(installed, update),
                      style: const TextStyle(
                        fontSize: AppTypography.caption,
                        color: AppColors.riskText,
                        height: 1.5,
                      ),
                    ),
                  ],
                  if (update.releaseNotes.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 10),
                    Text(
                      update.releaseNotes,
                      style: const TextStyle(
                        fontSize: AppTypography.body,
                        color: AppColors.inkSoft,
                        height: 1.7,
                      ),
                    ),
                  ],
                  if (update.fileSize > 0) ...<Widget>[
                    const SizedBox(height: 10),
                    Text(
                      '安装包约 ${_formatMegabytes(update.fileSize)}',
                      style: const TextStyle(
                        fontSize: AppTypography.caption,
                        color: AppColors.crackle,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: AppSpacing.content),
            SurfaceCard(
              color: AppColors.riskSurface,
              shadow: const <BoxShadow>[],
              child: Row(
                children: <Widget>[
                  const Icon(Icons.error_outline, color: AppColors.kilnRed),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: AppTypography.caption,
                        color: AppColors.riskText,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 22),
          if (available)
            FilledButton.icon(
              onPressed: _opening ? null : _download,
              icon: const Icon(Icons.download_outlined, size: 18),
              label: Text(_opening ? '正在打开…' : '下载新版本'),
            )
          else
            OutlinedButton.icon(
              onPressed: _checking ? null : _run,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(_checking ? '检查中…' : '重新检查'),
            ),
          const SizedBox(height: 14),
          const Text(
            '下载走系统浏览器，安装完成后当前应用会被覆盖升级；你的行程、收藏与账号数据都保存在服务端，不会因为升级丢失。',
            style: TextStyle(
              fontSize: AppTypography.caption,
              color: AppColors.crackle,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  String _statusText(AppUpdateInfo? update, bool required, bool available) {
    if (_checking) {
      return '正在检查…';
    }
    if (_error != null || update == null) {
      return '检查失败';
    }
    if (!update.releaseAvailable) {
      return '服务端还没有可用的安装包';
    }
    if (!available) {
      return '已是最新版本';
    }
    return required ? '需要更新' : '有新版本可用';
  }

  /// 强制更新的原因要如实说，不能只丢一句"必须更新"。
  String _requiredReason(InstalledAppInfo? installed, AppUpdateInfo update) {
    final int current = installed?.versionCode ?? 0;
    if (current < update.minimumSupportedVersionCode) {
      return '当前版本低于服务端支持的最低版本'
          '（${update.minimumSupportedVersionCode}），继续使用会出现接口对不上的问题。';
    }
    return '你停留的版本已经落后很多，继续使用可能遇到无法解释的报错，建议立即升级。';
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({
    required this.label,
    required this.value,
    this.tone = AppColors.ink,
  });

  final String label;
  final String value;
  final Color tone;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: AppTypography.caption,
                color: AppColors.crackle,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: AppTypography.body,
                fontWeight: FontWeight.w600,
                color: tone,
              ),
            ),
          ),
        ],
      );
}

/// 安装包大小只用来给用户一个"要不要现在下"的判断，一位小数足够。
String _formatMegabytes(int bytes) =>
    '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
