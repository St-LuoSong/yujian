import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../app.dart';
import 'bootstrap.dart';
import 'providers.dart';

/// 应用根节点：先把平台服务准备好，再挂载真正的主页。
///
/// 为什么要把初始化搬到 widget 树里，而不是继续在 main() 里 await：
///
/// 以前 main() 会一直等到安全存储、缓存和配置全部就绪才 runApp，这段时间
/// Flutter 一帧都还没画，屏幕上只有 Android 的原生启动背景。把初始化搬进来
/// 之后，第一帧就是完整的山水加载页，慢启动时用户看到的是"正在加载"，
/// 而不是一个静止的图标。
///
/// 初始化失败不再是一个白屏：这里给出明确的失败态和"重新加载"，不会无限转圈。
class YujianBootstrap extends StatefulWidget {
  const YujianBootstrap({super.key});

  @override
  State<YujianBootstrap> createState() => _YujianBootstrapState();
}

class _YujianBootstrapState extends State<YujianBootstrap> {
  /// 加载页最短展示时长：太短会变成一闪而过的白屏，反而更像闪屏。
  static const Duration _minimumSplash = Duration(milliseconds: 600);
  static const Duration _reducedMotionSplash = Duration(milliseconds: 150);
  static const Duration _fadeDuration = Duration(milliseconds: 240);

  AppBootstrap? _bootstrap;
  bool _loading = true;
  bool _started = false;
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!_started) {
      _started = true;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    final DateTime startedAt = DateTime.now();
    try {
      final AppBootstrap value = await AppBootstrap.create();
      final Duration minimum =
          _reduceMotion ? _reducedMotionSplash : _minimumSplash;
      final Duration elapsed = DateTime.now().difference(startedAt);
      if (elapsed < minimum) {
        await Future<void>.delayed(minimum - elapsed);
      }
      if (!mounted) return;
      setState(() {
        _bootstrap = value;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      // 失败原因留在日志里，界面上只给用户"重新加载"这一步 ——
      // 把平台异常原文摊给游客看，既看不懂也不安全。
      debugPrint('YujianBootstrap failed: $error');
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppBootstrap? bootstrap = _bootstrap;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: AnimatedSwitcher(
        duration: _reduceMotion ? Duration.zero : _fadeDuration,
        child: bootstrap == null
            ? MaterialApp(
                key: const ValueKey<String>('startup'),
                debugShowCheckedModeBanner: false,
                title: '豫见智旅',
                home: _loading
                    ? const StartupSplash()
                    : StartupFailure(onRetry: _load),
              )
            : ProviderScope(
                key: const ValueKey<String>('app'),
                overrides: <Override>[
                  appBootstrapProvider.overrideWithValue(bootstrap),
                ],
                child: const YujianApp(),
              ),
      ),
    );
  }
}

/// 启动加载页。
///
/// 图随 APK 打包（assets/brand/loading.png），不从网络读取：第一次启动、
/// 断网、服务器不可用时都要能显示。整屏 cover 铺满，底部只留一条细进度条，
/// 避免遮住画面里的标题、塔与石窟。
///
/// 为什么是"品牌青打底 + 海报淡入"：Android 12 以上的系统启动页只能是纯色
/// 加一个居中图标（平台限制，画不了整幅图），那一屏的底色就是下面这个颜色。
/// 海报在这里用 280ms 淡入，衔接过去才像设计的一部分，而不是"先看到一块色、
/// 又突然换一张图"。
class StartupSplash extends StatelessWidget {
  const StartupSplash({super.key});

  /// 与 android/app/src/main/res/values/colors.xml 的 yujian_splash_bg 一致。
  static const Color _splashGround = Color(0xFF34776C);

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final Widget poster = Image.asset(
      'assets/brand/loading.png',
      fit: BoxFit.cover,
      // 素材是 266×523 的海报，手机会放大好几倍，
      // 用 high 让它落在高分辨率屏上不至于糊成一片。
      filterQuality: FilterQuality.high,
      // 装饰性图片，语义由外层 Semantics 提供。
      excludeFromSemantics: true,
    );
    return Semantics(
      container: true,
      label: '豫见智旅正在加载',
      child: ColoredBox(
        color: _splashGround,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (reduceMotion)
              poster
            else
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOut,
                builder: (BuildContext context, double value, Widget? child) =>
                    Opacity(opacity: value, child: child),
                child: poster,
              ),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: LinearProgressIndicator(
                minHeight: 3,
                // 底色是深青，进度条改用麦穗金才看得见。
                color: Color(0xFFE8B45B),
                backgroundColor: Color(0x33FFFFFF),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 初始化失败的兜底页：说清发生了什么，并给一个可以再试一次的按钮。
class StartupFailure extends StatelessWidget {
  const StartupFailure({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ground,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.section),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '应用初始化失败',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.small),
              Text(
                '本地缓存或安全存储暂时不可用，请重新加载。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.section),
              FilledButton(
                onPressed: onRetry,
                child: const Text('重新加载'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
