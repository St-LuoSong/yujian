import 'package:flutter/material.dart';

/// 页面左上角的返回按钮：显式、常驻、永远有一个出口。
///
/// 为什么不用 `AppBar` 的自动 leading：它只在 `ModalRoute.impliesAppBarDismissal`
/// （也就是"这条路由下面还有活动路由"）为真时才会渲染。这个条件跟着导航栈的
/// 形态变化，一旦不成立，`AppBar` 会**静默地**不给返回按钮 —— 用户就卡在这一页
/// 出不去了，而且没有任何报错可查。把 leading 写死，等于把这个变量从界面上删掉。
///
/// [fallback] 是最后一道保险：万一这一页真的成了栈底（`canPop()` 为假），
/// 用重建主导航壳层的方式退出，而不是让按钮点下去毫无反应。
class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key, this.fallback, this.tooltip = '返回'});

  /// 没有上一层可退时，用来重建导航壳层的页面构造器。为空时按钮只做 pop。
  final WidgetBuilder? fallback;

  final String tooltip;

  @override
  Widget build(BuildContext context) => IconButton(
        onPressed: () => _leave(context),
        tooltip: tooltip,
        icon: const Icon(Icons.arrow_back, size: 20),
      );

  void _leave(BuildContext context) {
    final NavigatorState navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.maybePop();
      return;
    }
    final WidgetBuilder? rescue = fallback;
    if (rescue == null) {
      return;
    }
    navigator.pushAndRemoveUntil<void>(
      MaterialPageRoute<void>(builder: rescue),
      (Route<dynamic> route) => false,
    );
  }
}
