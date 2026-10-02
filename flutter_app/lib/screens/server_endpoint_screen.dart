import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/config/app_config.dart';
import '../core/network/dio_factory.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/widgets/surface_card.dart';

/// Lets a release APK point at a deployed backend without rebuilding.
///
/// The address is tested against `/home` before it is saved. A user can still
/// choose "仅保存" when the backend is temporarily offline; this keeps the
/// product usable on a LAN without pretending the test passed.
class ServerEndpointScreen extends ConsumerStatefulWidget {
  const ServerEndpointScreen({super.key});

  @override
  ConsumerState<ServerEndpointScreen> createState() =>
      _ServerEndpointScreenState();
}

class _ServerEndpointScreenState extends ConsumerState<ServerEndpointScreen> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: ref.read(appConfigProvider).apiBaseUrl);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppConfig config = ref.watch(appConfigProvider);
    final double page = AppSpacing.pageFor(MediaQuery.sizeOf(context).width);
    final bool locked = config.lockedByBuild;

    return Scaffold(
      backgroundColor: AppColors.ground,
      appBar: AppBar(title: const Text('服务器地址')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(page, 8, page, 36),
        children: <Widget>[
          const Text(
            '这个地址用于连接豫见智旅后端。测试者不需要重新打包，只要服务器开放了 HTTPS，'
            '就可以在这里切换。',
            style: TextStyle(
              fontSize: AppTypography.lead,
              color: AppColors.inkSoft,
              height: 1.6,
            ),
          ),
          const SizedBox(height: AppSpacing.section),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  '当前地址',
                  style: TextStyle(
                    fontSize: AppTypography.cardTitle,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  config.apiBaseUrl.isEmpty ? '未配置' : config.apiBaseUrl,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: AppTypography.caption,
                    color: AppColors.celadonDeep,
                  ),
                ),
                if (locked) ...<Widget>[
                  const SizedBox(height: 10),
                  const Text(
                    '当前安装包使用编译期地址，设置页不能覆盖它。',
                    style: TextStyle(
                      fontSize: AppTypography.caption,
                      color: AppColors.riskText,
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.content),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TextField(
                  controller: _controller,
                  enabled: !locked,
                  autocorrect: false,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: '服务器地址',
                    hintText: 'https://travel.example.com/api',
                    helperText: '可以只填域名，系统会自动补 https:// 和 /api',
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  '本机调试可用 http://10.0.2.2:8080/api；正式交付请使用 HTTPS。',
                  style: TextStyle(
                    fontSize: AppTypography.caption,
                    color: AppColors.crackle,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                if (!locked)
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: FilledButton(
                          onPressed: _busy ? null : () => _save(tested: true),
                          child: Text(_busy ? '测试中…' : '测试并保存'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy ? null : () => _save(tested: false),
                          child: const Text('仅保存'),
                        ),
                      ),
                    ],
                  ),
                if (_message != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    _message!,
                    style: TextStyle(
                      fontSize: AppTypography.caption,
                      color: _failed
                          ? AppColors.riskText
                          : AppColors.celadonDeep,
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _busy = false;
  bool _failed = false;
  String? _message;

  Future<void> _save({required bool tested}) async {
    final String raw = _controller.text.trim();
    final String? normalized = AppConfig.normalizeUserEndpoint(raw);
    if (normalized == null) {
      setState(() {
        _failed = true;
        _message = kReleaseMode
            ? '地址格式不正确，正式包必须使用 https:// 开头。'
            : '地址格式不正确，请填写 http(s)://host:port/api。';
      });
      return;
    }

    setState(() {
      _busy = true;
      _failed = false;
      _message = tested ? '正在测试连接…' : '正在保存…';
    });

    if (tested) {
      final AppConfig candidate = ref.read(appConfigProvider).withEndpoint(normalized);
      try {
        final Dio dio = buildBareDio(candidate);
        await dio.get<Map<String, dynamic>>('/home');
      } on DioException catch (error) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _failed = true;
          _message = error.message == null
              ? '连接失败，请检查地址、证书与网络。'
              : '连接失败：${error.message}';
        });
        return;
      } on Object {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _failed = true;
          _message = '连接失败，请检查地址与网络。';
        });
        return;
      }
    }

    try {
      await ref.read(appConfigProvider.notifier).updateEndpoint(normalized);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(tested ? '连接成功，服务器地址已更新。' : '服务器地址已保存。'),
        ));
      Navigator.of(context).pop();
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = true;
        _message = '保存失败，请检查地址后重试。';
      });
    }
  }
}
