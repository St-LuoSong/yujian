import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/account_repository.dart';
import '../models/account_models.dart';
import 'providers.dart';

/// Who is signed in, or null while nobody is.
///
/// Restores the stored session on first read. A stale token resolves to null;
/// any other failure surfaces as an error, so an offline user is not silently
/// presented as signed out.
final sessionProvider = AsyncNotifierProvider<SessionController, UserProfile?>(
  SessionController.new,
);

class SessionController extends AsyncNotifier<UserProfile?> {
  AccountRepository get _repository => ref.read(accountRepositoryProvider);

  /// Who is signed in according to the newest local decision.
  ///
  /// [build] runs [AccountRepository.restore], which can take a while when a
  /// stored token has to be checked against `/auth/me`. If the user signs in
  /// while that read is still in flight, the restored value must not be allowed
  /// to overwrite the account they just created — otherwise the app looks
  /// signed out immediately after a successful login ("登录后没有反应"),
  /// which is exactly the bug this counter prevents.
  int _adoptions = 0;
  UserProfile? _current;

  @override
  Future<UserProfile?> build() async {
    final int adoptionsAtStart = _adoptions;
    final UserProfile? restored =
        await ref.watch(accountRepositoryProvider).restore();
    if (adoptionsAtStart != _adoptions) {
      // A newer sign in / sign out decision won the race; it stays in charge.
      return _current;
    }
    _current = restored;
    return restored;
  }

  Future<SignInOutcome> signIn({
    required String identifier,
    required String password,
  }) async {
    final outcome = await _repository.signIn(
      identifier: identifier,
      password: password,
    );
    _adopt(outcome.user);
    return outcome;
  }

  Future<SignInOutcome> register({
    required String username,
    required String email,
    required String password,
  }) async {
    final outcome = await _repository.register(
      username: username,
      email: email,
      password: password,
    );
    _adopt(outcome.user);
    return outcome;
  }

  /// Hands the anonymous trial trip over to the account that just signed in.
  ///
  /// Runs after the session already switched to the signed in user, so neither
  /// a slow nor a failing handover can look like a stuck sign in.
  Future<AnonymousMergeOutcome> mergeAnonymousTrips() =>
      _repository.mergeAnonymousTrips();

  Future<void> signOut() async {
    await _repository.signOut();
    _adopt(null);
  }

  /// Refreshes `/auth/me` after a profile edit or email verification.
  Future<void> refreshProfile() async {
    _adopt(await _repository.restore());
  }

  Future<UserProfile> updateProfile({
    required String? nickname,
    required String? avatarKey,
  }) async {
    final user = await _repository.updateProfile(
      nickname: nickname,
      avatarKey: avatarKey,
    );
    _adopt(user);
    return user;
  }

  /// 上传自定义头像。服务端返回的是更新后的用户，直接用它刷新会话。
  Future<UserProfile> uploadAvatar(File file) async {
    final user = await _repository.uploadAvatar(file);
    _adopt(user);
    return user;
  }

  /// 移除自定义头像，回到预设或默认图案。
  Future<UserProfile> removeAvatar() async {
    final user = await _repository.removeAvatar();
    _adopt(user);
    return user;
  }

  /// Changing the password revokes refresh tokens, so this device signs out
  /// and asks the user to log in again with the new password.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _repository.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
    await _repository.signOut();
    _adopt(null);
  }

  Future<void> logoutAllDevices() async {
    try {
      await _repository.logoutAllDevices();
    } finally {
      _adopt(null);
    }
  }

  Future<void> deleteAccount(String password) async {
    await _repository.deleteAccount(password);
    _adopt(null);
  }

  void _adopt(UserProfile? user) {
    _adoptions++;
    _current = user;
    state = AsyncData(user);
    // 收藏是跟账号走的，所以它必须跟着会话刷新 —— 但**不能**在这里
    // `ref.invalidate(favoritesProvider)`：favoritesProvider 自己 watch 了
    // sessionProvider，从 sessionProvider 内部去 invalidate 它构成循环依赖，
    // Riverpod 在 debug 构建里直接抛 CircularDependencyError。这条断言就长在
    // 登录回调里，于是「账号密码都对」的登录会弹一句「登录没有完成，请稍后重试」。
    //
    // 正确做法是让依赖自己生效：state 一变，watch 了 sessionProvider 的
    // favoritesProvider 会自动重建，效果一样且没有反向依赖。
  }
}

/// Favourites of the signed in user.
///
/// Empty while signed out: the server stores favourites per account, so the
/// client must not invent a local list that would vanish on the next sync.
final favoritesProvider =
    AsyncNotifierProvider<FavoritesController, List<FavoriteItem>>(
  FavoritesController.new,
);

class FavoritesController extends AsyncNotifier<List<FavoriteItem>> {
  @override
  Future<List<FavoriteItem>> build() async {
    final user = ref.watch(sessionProvider).valueOrNull;
    if (user == null) {
      return const <FavoriteItem>[];
    }
    return ref.watch(accountRepositoryProvider).listFavorites();
  }

  bool contains(String poiId) => (state.valueOrNull ?? const <FavoriteItem>[])
      .any((item) => item.poiId == poiId);

  /// Adds or removes, then refreshes from the server so the list cannot drift.
  Future<void> toggle({
    required String poiId,
    required String poiName,
    String? city,
    String? imageUrl,
  }) async {
    final repository = ref.read(accountRepositoryProvider);
    if (contains(poiId)) {
      await repository.removeFavorite(poiId);
    } else {
      await repository.addFavorite(
        poiId: poiId,
        poiName: poiName,
        city: city,
        imageUrl: imageUrl,
      );
    }
    ref.invalidateSelf();
    await future;
  }
}
