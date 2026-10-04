import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../app/providers.dart';
import '../app/session_providers.dart';
import '../core/icons/app_icons.dart';
import '../core/network/api_failure.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/widgets/surface_card.dart';
import '../core/widgets/user_avatar.dart';

const List<_AvatarOption> _avatarOptions = <_AvatarOption>[
  _AvatarOption('celadon', '山河', Icons.landscape_outlined),
  _AvatarOption('kiln', '古建', Icons.account_balance_outlined),
  _AvatarOption('amber', '日光', Icons.wb_sunny_outlined),
  _AvatarOption('river', '河流', Icons.water_outlined),
  _AvatarOption('ink', '灵感', Icons.auto_awesome_outlined),
];

/// 编辑昵称与头像。
///
/// 头像有两条路：预设图案（只存一个键）与自定义照片（上传到服务端媒体库，
/// 存储时重新编码并去掉 EXIF，所以不会把拍摄位置一起公开出去）。
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final TextEditingController _nickname;
  final ImagePicker _picker = ImagePicker();
  String? _avatarKey;
  String? _avatarUrl;
  bool _saving = false;
  bool _avatarBusy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = ref.read(sessionProvider).valueOrNull;
    _nickname = TextEditingController(text: user?.nickname ?? '');
    _avatarKey = user?.avatarKey;
    _avatarUrl = _resolveAvatar(user?.avatarUrl);
  }

  /// 服务端存的是 /media/... 相对路径，预览前补成这台设备能访问的地址。
  String? _resolveAvatar(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    return ref.read(appConfigProvider).resolveMediaUrl(raw);
  }

  @override
  void dispose() {
    _nickname.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double page = AppSpacing.pageFor(MediaQuery.sizeOf(context).width);
    return Scaffold(
      backgroundColor: AppColors.ground,
      appBar: AppBar(title: const Text('个人信息')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(page, 8, page, 36),
        children: <Widget>[
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  '昵称',
                  style: TextStyle(
                    fontSize: AppTypography.cardTitle,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _nickname,
                  maxLength: 40,
                  decoration: const InputDecoration(
                    hintText: '留空则显示用户名',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  '头像',
                  style: TextStyle(
                    fontSize: AppTypography.cardTitle,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 12),
                // 照片与预设图案是两种来源，同一时刻只呈现一种选择方式：
                // 同时摆着"选预设"和"换照片"，用户点完两个会得到什么就说不清了。
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    UserAvatar(
                      name: _nickname.text.trim().isEmpty
                          ? '我'
                          : _nickname.text.trim(),
                      imageUrl: _avatarUrl,
                      avatarKey: _avatarKey,
                      size: 64,
                      borderColor: AppColors.hairline,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            _avatarUrl == null
                                ? '当前使用预设图案或用户名首字。'
                                : '当前使用你上传的照片。',
                            style: const TextStyle(
                              fontSize: AppTypography.caption,
                              color: AppColors.crackle,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: <Widget>[
                              OutlinedButton.icon(
                                onPressed: _avatarBusy ? null : _pickAvatar,
                                icon: const AppIcon(
                                  AppIcons.upload,
                                  size: 16,
                                  color: AppColors.celadonDeep,
                                ),
                                label: Text(
                                  _avatarBusy
                                      ? '上传中…'
                                      : (_avatarUrl == null ? '上传照片' : '更换照片'),
                                ),
                              ),
                              if (_avatarUrl != null)
                                TextButton(
                                  onPressed: _avatarBusy ? null : _removeAvatar,
                                  child: const Text('移除照片'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_avatarUrl != null) ...<Widget>[
                  const SizedBox(height: 10),
                  const Text(
                    '照片会先重新编码并去掉位置信息，再作为头像公开；移除后回到预设图案。',
                    style: TextStyle(
                      fontSize: AppTypography.caption,
                      color: AppColors.crackle,
                      height: 1.5,
                    ),
                  ),
                ] else ...<Widget>[
                  const SizedBox(height: 16),
                  const Text(
                    '或选择一个预设图案',
                    style: TextStyle(
                      fontSize: AppTypography.caption,
                      color: AppColors.crackle,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: <Widget>[
                      _AvatarChoice(
                        label: '首字',
                        icon: null,
                        selected: _avatarKey == null,
                        onTap: () => setState(() => _avatarKey = null),
                      ),
                      for (final option in _avatarOptions)
                        _AvatarChoice(
                          label: option.label,
                          icon: option.icon,
                          selected: _avatarKey == option.key,
                          onTap: () => setState(() => _avatarKey = option.key),
                        ),
                    ],
                  ),
                ],
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: const TextStyle(
                      fontSize: AppTypography.caption,
                      color: AppColors.riskText,
                      height: 1.5,
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? '保存中…' : '保存个人信息'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 选一张照片并立刻上传。
  ///
  /// 与保存昵称分开：这一条会真的改变服务端上的头像文件，上传成功就已经生效了。
  /// 如果等"保存个人信息"再传，用户在这一页停留的每一秒都在赌网络。
  Future<void> _pickAvatar() async {
    if (_avatarBusy) return;
    final XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
      );
    } on Object {
      if (mounted) setState(() => _error = '无法打开相册，请检查系统权限。');
      return;
    }
    if (picked == null || !mounted) return;

    setState(() {
      _avatarBusy = true;
      _error = null;
    });
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final user =
          await ref.read(sessionProvider.notifier).uploadAvatar(File(picked.path));
      if (!mounted) return;
      setState(() {
        _avatarUrl = _resolveAvatar(user.avatarUrl);
        // 上传会顶掉预设图案，两边的本地状态必须一起更新，否则预览和保存
        // 送出去的值会不一致。
        _avatarKey = user.avatarKey;
        _avatarBusy = false;
      });
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('头像已更新。')));
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _avatarBusy = false;
        _error = failure.message;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _avatarBusy = false;
        _error = '头像上传失败，请稍后重试。';
      });
    }
  }

  Future<void> _removeAvatar() async {
    if (_avatarBusy) return;
    setState(() {
      _avatarBusy = true;
      _error = null;
    });
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final user = await ref.read(sessionProvider.notifier).removeAvatar();
      if (!mounted) return;
      setState(() {
        _avatarUrl = _resolveAvatar(user.avatarUrl);
        _avatarKey = user.avatarKey;
        _avatarBusy = false;
      });
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('已移除自定义头像。')));
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _avatarBusy = false;
        _error = failure.message;
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).updateProfile(
            nickname: _nickname.text.trim(),
            avatarKey: _avatarKey,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('个人信息已更新。')));
      Navigator.of(context).pop();
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = failure.message;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '保存失败，请稍后重试。';
      });
    }
  }
}

/// 修改密码。成功后服务端撤销所有刷新令牌，本机要求重新登录。
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _next = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _saving = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double page = AppSpacing.pageFor(MediaQuery.sizeOf(context).width);
    return Scaffold(
      backgroundColor: AppColors.ground,
      appBar: AppBar(title: const Text('修改密码')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(page, 8, page, 36),
        children: <Widget>[
          const Text(
            '修改成功后，所有设备的刷新令牌都会被撤销；本机需要重新登录。',
            style: TextStyle(
              fontSize: AppTypography.lead,
              color: AppColors.inkSoft,
              height: 1.6,
            ),
          ),
          const SizedBox(height: AppSpacing.section),
          SurfaceCard(
            child: Column(
              children: <Widget>[
                _PasswordField(
                  controller: _current,
                  label: '当前密码',
                  obscure: _obscure,
                ),
                const SizedBox(height: 14),
                _PasswordField(
                  controller: _next,
                  label: '新密码（8—72 位）',
                  obscure: _obscure,
                ),
                const SizedBox(height: 14),
                _PasswordField(
                  controller: _confirm,
                  label: '再次输入新密码',
                  obscure: _obscure,
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Checkbox(
                      value: !_obscure,
                      onChanged: (value) => setState(() => _obscure = !(value ?? false)),
                    ),
                    const Text('显示密码'),
                  ],
                ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
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
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _submit,
                    child: Text(_saving ? '提交中…' : '修改密码'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (_current.text.isEmpty) {
      setState(() => _error = '请输入当前密码');
      return;
    }
    if (_next.text.length < 8 || _next.text.length > 72) {
      setState(() => _error = '新密码长度应为 8—72 位');
      return;
    }
    if (_next.text != _confirm.text) {
      setState(() => _error = '两次输入的新密码不一致');
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(sessionProvider.notifier).changePassword(
            currentPassword: _current.text,
            newPassword: _next.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('密码已修改，请用新密码重新登录。')));
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = failure.message;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '修改失败，请稍后重试。';
      });
    }
  }
}

/// 邮箱验证：发送验证码、校验后刷新 /auth/me 的 emailVerified。
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  final TextEditingController _code = TextEditingController();
  bool _sending = false;
  bool _verifying = false;
  String? _message;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider).valueOrNull;
    final double page = AppSpacing.pageFor(MediaQuery.sizeOf(context).width);
    return Scaffold(
      backgroundColor: AppColors.ground,
      appBar: AppBar(title: const Text('邮箱验证')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(page, 8, page, 36),
        children: <Widget>[
          Text(
            user == null || user.email.isEmpty
                ? '当前没有可验证的邮箱。'
                : '验证码会发送到 ${user.email}。',
            style: const TextStyle(
              fontSize: AppTypography.lead,
              color: AppColors.inkSoft,
              height: 1.6,
            ),
          ),
          const SizedBox(height: AppSpacing.section),
          SurfaceCard(
            child: Column(
              children: <Widget>[
                TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: '六位验证码',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _sending || user == null ? null : _send,
                        child: Text(_sending ? '发送中…' : '发送验证码'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: _verifying || user == null ? null : _verify,
                        child: Text(_verifying ? '验证中…' : '确认验证'),
                      ),
                    ),
                  ],
                ),
                if (_message != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    _message!,
                    style: const TextStyle(
                      fontSize: AppTypography.caption,
                      color: AppColors.celadonDeep,
                      height: 1.5,
                    ),
                  ),
                ],
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(
                      fontSize: AppTypography.caption,
                      color: AppColors.riskText,
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

  Future<void> _send() async {
    final user = ref.read(sessionProvider).valueOrNull;
    if (user == null) return;
    setState(() {
      _sending = true;
      _message = null;
      _error = null;
    });
    try {
      final result = await ref.read(accountRepositoryProvider).sendEmailCode(user.email);
      if (!mounted) return;
      setState(() {
        _sending = false;
        _message = result.debugCode == null
            ? result.message
            : '${result.message}（开发验证码：${result.debugCode}）';
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = failure.message;
      });
    }
  }

  Future<void> _verify() async {
    final user = ref.read(sessionProvider).valueOrNull;
    if (user == null) return;
    if (_code.text.trim().length != 6) {
      setState(() => _error = '请输入六位验证码');
      return;
    }
    setState(() {
      _verifying = true;
      _message = null;
      _error = null;
    });
    try {
      final result = await ref.read(accountRepositoryProvider).verifyEmailCode(user.email, _code.text);
      await ref.read(sessionProvider.notifier).refreshProfile();
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _message = result.message;
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _error = failure.message;
      });
    }
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.obscure,
  });

  final TextEditingController controller;
  final String label;
  final bool obscure;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        obscureText: obscure,
        decoration: InputDecoration(labelText: label),
      );
}

class _AvatarChoice extends StatelessWidget {
  const _AvatarChoice({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Column(
        children: <Widget>[
          InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? AppColors.celadonDeep : AppColors.surfaceTint,
                border: Border.all(
                  color: selected ? AppColors.amber : AppColors.hairline,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Icon(
                icon ?? Icons.person_outline,
                color: selected ? AppColors.onInk : AppColors.celadonDeep,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: AppTypography.caption,
              color: selected ? AppColors.celadonDeep : AppColors.crackle,
            ),
          ),
        ],
      );
}

class _AvatarOption {
  const _AvatarOption(this.key, this.label, this.icon);

  final String key;
  final String label;
  final IconData icon;
}
