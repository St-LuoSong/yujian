import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/session_providers.dart';
import '../core/network/api_failure.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/widgets/surface_card.dart';
import '../models/account_models.dart';

/// Sign in / register as a full page rather than a form bolted onto the profile
/// tab.
///
/// The v0.2 version was two text fields and a button sitting directly under the
/// tab bar, which read as a placeholder. This page states what an account is
/// for before it asks for anything, and switching between 登录 and 注册 is an
/// animated control instead of a text link.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final TextEditingController _identifier = TextEditingController();
  final TextEditingController _username = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final FocusNode _passwordFocus = FocusNode();

  bool _registering = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _identifier.dispose();
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double page = AppSpacing.pageFor(MediaQuery.sizeOf(context).width);
    return Scaffold(
      backgroundColor: AppColors.ground,
      appBar: AppBar(title: Text(_registering ? '注册账号' : '登录')),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(page, 4, page, 32),
        children: <Widget>[
          const _AccountHero(),
          const SizedBox(height: AppSpacing.section),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _ModeSwitch(
                  registering: _registering,
                  onChanged: _busy
                      ? null
                      : (bool value) => setState(() {
                            _registering = value;
                            _error = null;
                          }),
                ),
                const SizedBox(height: 20),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: Column(
                    key: ValueKey<bool>(_registering),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (_registering) ...<Widget>[
                        TextField(
                          controller: _username,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: '用户名',
                            hintText: '3—32 个字符',
                            prefixIcon: Icon(Icons.badge_outlined, size: 18),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: '邮箱',
                            hintText: '用于找回账号（SMTP 为预留能力）',
                            prefixIcon: Icon(Icons.mail_outline, size: 18),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ] else ...<Widget>[
                        TextField(
                          controller: _identifier,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: '用户名或邮箱',
                            prefixIcon: Icon(Icons.person_outline, size: 18),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        controller: _password,
                        focusNode: _passwordFocus,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          labelText: '密码',
                          hintText: _registering ? '至少 8 位' : null,
                          prefixIcon: const Icon(Icons.lock_outline, size: 18),
                          suffixIcon: IconButton(
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                            tooltip: _obscure ? '显示密码' : '隐藏密码',
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 18,
                            ),
                          ),
                        ),
                        onSubmitted: (_) => _submit(),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 14),
                  _ErrorBanner(message: _error!),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.onInk,
                            ),
                          )
                        : Text(_registering ? '注册并登录' : '登录'),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '密码只提交给服务器，不保存在本地；登录后匿名体验的行程会自动合并到账号。',
                  style: TextStyle(
                    fontSize: AppTypography.caption,
                    color: AppColors.crackle,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const _BenefitCard(),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('先随便逛逛，稍后再登录'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final String identifier = _identifier.text.trim();
    final String username = _username.text.trim();
    final String email = _email.text.trim();
    final String password = _password.text;

    if (_registering) {
      if (username.isEmpty || email.isEmpty || password.isEmpty) {
        setState(() => _error = '请填写用户名、邮箱和密码。');
        return;
      }
      if (password.length < 8) {
        setState(() => _error = '密码至少 8 位。');
        return;
      }
    } else if (identifier.isEmpty || password.isEmpty) {
      setState(() => _error = '请填写账号和密码。');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);
    // Read the notifier up front: the handover below outlives this page, so it
    // must not touch this widget's ref afterwards.
    final SessionController controller = ref.read(sessionProvider.notifier);

    // 只有凭据交换能判定「登录失败」。它下面的每一步（关页面、提示、匿名行程
    // 交接）都是表现层：账号其实已经可用了，那些地方出问题绝不能再被报成
    // 「登录没有完成」——正是这种混淆让一次成功的登录看起来像卡住了。
    final SignInOutcome outcome;
    try {
      outcome = _registering
          ? await controller.register(
              username: username,
              email: email,
              password: password,
            )
          : await controller.signIn(
              identifier: identifier,
              password: password,
            );
    } on ApiFailure catch (failure) {
      // 服务器给得出理由就照实显示（密码错误、限流、超时……），不吞掉。
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = failure.message;
      });
      return;
    } on Object catch (error, stackTrace) {
      // 不是 ApiFailure，说明问题在客户端本身。留下可排查的现场
      // （`flutter logs` / logcat 里能看到），同时给用户一条可执行的话，
      // 而不是一句没有信息量的「请稍后重试」。
      debugPrint('[account] sign in failed: $error\n$stackTrace');
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = '登录没有完成（${error.runtimeType}），请重试。';
      });
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _error = null;
    });
    _password.clear();
    try {
      navigator.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(_signedInMessage(outcome))));
    } on Object catch (error) {
      // 账号已经生效，这里失败也不该把用户按在登录页上。
      debugPrint('[account] signed in, but the page could not close: $error');
    }
    if (outcome.mergePending) {
      // Reported where the user ended up, not where they signed in from.
      unawaited(_handOverTrialTrips(controller, messenger));
    }
  }

  String _signedInMessage(SignInOutcome outcome) =>
      outcome.mergePending ? '已登录，正在同步匿名体验的行程…' : '已登录。';

  /// Carries the anonymous trial trip over after the page is already gone.
  ///
  /// [controller] and [messenger] are captured before the pop: this work
  /// continues while the login page is unmounted, and the notice has to follow
  /// the user wherever they went.
  Future<void> _handOverTrialTrips(
    SessionController controller,
    ScaffoldMessengerState messenger,
  ) async {
    final AnonymousMergeOutcome outcome = await controller.mergeAnonymousTrips();
    final String? message;
    if (outcome.merged) {
      message = '匿名体验的行程已合并到账号。';
    } else if (outcome.failure != null) {
      message = '已登录，但匿名行程未能合并：${outcome.failure!.message}';
    } else {
      message = null;
    }
    if (message == null) {
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// States the value of an account before asking for credentials.
class _AccountHero extends StatelessWidget {
  const _AccountHero();

  @override
  Widget build(BuildContext context) => SurfaceCard(
        color: AppColors.celadonDeep,
        shadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x33204F49),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    '豫',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onInk,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    '登录后，行程才真正属于你',
                    style: TextStyle(
                      fontSize: AppTypography.sectionTitle,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onInk,
                      height: AppTypography.headingHeight,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              '免登录也能浏览和体验一次规划；但要保存、收藏和分享，就需要一个账号。',
              style: TextStyle(
                fontSize: AppTypography.caption,
                color: AppColors.onInkMuted,
                height: 1.6,
              ),
            ),
          ],
        ),
      );
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.registering, required this.onChanged});

  final bool registering;

  /// Null while a request is in flight, which also disables both segments.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.ground,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: _Segment(
                label: '登录',
                active: !registering,
                onTap: onChanged == null ? null : () => onChanged!(false),
              ),
            ),
            Expanded(
              child: _Segment(
                label: '注册',
                active: registering,
                onTap: onChanged == null ? null : () => onChanged!(true),
              ),
            ),
          ],
        ),
      );
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: active,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? AppColors.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              boxShadow: active ? AppColors.chipShadow : null,
            ),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              style: TextStyle(
                fontSize: AppTypography.body,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? AppColors.ink : AppColors.crackle,
              ),
              child: Text(label),
            ),
          ),
        ),
      );
}

class _BenefitCard extends StatelessWidget {
  const _BenefitCard();

  static const List<({IconData icon, String title, String detail})> _items =
      <({IconData icon, String title, String detail})>[
    (
      icon: Icons.sync_outlined,
      title: '行程跟着账号走',
      detail: '换设备登录，最近生成的方案仍然在。',
    ),
    (
      icon: Icons.star_border,
      title: '收藏景区',
      detail: '把想去的石窟、古城和山景先收起来。',
    ),
    (
      icon: Icons.ios_share,
      title: '生成只读分享链接',
      detail: '同行的人用浏览器就能查看，不能改动原行程。',
    ),
  ];

  @override
  Widget build(BuildContext context) => SurfaceCard(
        color: AppColors.surfaceTint,
        shadow: const <BoxShadow>[],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              '为什么值得注册',
              style: TextStyle(
                fontSize: AppTypography.secondary,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 12),
            for (final ({IconData icon, String title, String detail}) item
                in _items)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(item.icon, size: 18, color: AppColors.celadonDeep),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            item.title,
                            style: const TextStyle(
                              fontSize: AppTypography.secondary,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.detail,
                            style: const TextStyle(
                              fontSize: AppTypography.caption,
                              color: AppColors.inkSoft,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(),
            const SizedBox(height: 10),
            const Text(
              '我们只保存账号必需的信息，不采集身份证号、银行卡号或后台定位历史。',
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

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.riskSurface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(
              Icons.error_outline,
              size: 16,
              color: AppColors.riskText,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: AppTypography.caption,
                  color: AppColors.riskText,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      );
}
