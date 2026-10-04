import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_failure.dart';
import '../../core/storage/session_store.dart';
import '../../models/account_models.dart';
import '../../models/message_models.dart';

/// Account bound operations: sign in, the anonymous trial handover, and the
/// favourite list.
///
/// Kept apart from the travel repository because these calls depend on who is
/// signed in, while the catalog and trip calls only depend on which session the
/// interceptor attached.
class AccountRepository {
  AccountRepository({required ApiClient client, required SessionStore session})
      : _client = client,
        _session = session;

  /// Upper bound for the optional trial handover.
  ///
  /// The account is already signed in when the handover runs, so this request
  /// must never be able to hold a screen hostage.
  static const Duration mergeTimeout = Duration(seconds: 8);

  final ApiClient _client;
  final SessionStore _session;

  /// Restores a stored session. Returns null when nobody is signed in.
  ///
  /// A stale token is cleared silently; any other failure is surfaced so an
  /// offline user is not told they were signed out.
  Future<UserProfile?> restore() async {
    final snapshot = await _session.read();
    if (!snapshot.hasUser) {
      return null;
    }
    try {
      return UserProfile.fromJson(await _client.getJsonObject('/auth/me'));
    } on ApiFailure catch (failure) {
      if (failure.requiresLogin) {
        // Only drop the session we actually tested: a sign in that landed
        // while this stale response was in flight must survive.
        await _session.clearUserSession(ifToken: snapshot.accessToken);
        return null;
      }
      rethrow;
    }
  }

  Future<SignInOutcome> signIn({
    required String identifier,
    required String password,
  }) async {
    final data = await _client.postJsonObject(
      '/auth/login',
      body: <String, Object?>{
        'identifier': identifier.trim(),
        'password': password,
      },
    );
    return _accept(AuthSession.fromJson(data));
  }

  Future<SignInOutcome> register({
    required String username,
    required String email,
    required String password,
  }) async {
    final data = await _client.postJsonObject(
      '/auth/register',
      body: <String, Object?>{
        'username': username.trim(),
        'email': email.trim(),
        'password': password,
      },
    );
    return _accept(AuthSession.fromJson(data));
  }

  /// Revokes the refresh token and clears local credentials.
  ///
  /// Local sign out always succeeds, even when the server cannot be reached.
  Future<void> signOut() async {
    final refreshToken = (await _session.read()).refreshToken;
    try {
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await _client.sendNoContent(
          () => _client.post<dynamic>(
            '/auth/logout',
            data: <String, Object?>{'refreshToken': refreshToken},
          ),
        );
      }
    } on ApiFailure {
      // Nothing to do: the credential is dropped locally below.
    } finally {
      await _session.clearUserSession();
    }
  }

  Future<UserProfile> updateProfile({
    required String? nickname,
    required String? avatarKey,
  }) async {
    final data = await _client.patchJsonObject(
      '/auth/me',
      body: <String, Object?>{
        'nickname': nickname,
        'avatarKey': avatarKey,
      },
    );
    return UserProfile.fromJson(data);
  }

  /// 上传自定义头像。
  ///
  /// 与旅记图片共用服务端的重编码链路（去 EXIF、服务端生成文件名），
  /// 客户端只负责把选中的文件送上去。
  Future<UserProfile> uploadAvatar(File file) async {
    try {
      final data = await _client
          .postMultipartJson(
            '/auth/me/avatar',
            data: FormData.fromMap(<String, Object>{
              'file': await MultipartFile.fromFile(file.path),
            }),
          )
          // 头像文件比旅记配图小得多，卡到 45 秒说明网络已经不可用了。
          .timeout(const Duration(seconds: 30));
      return UserProfile.fromJson(data);
    } on TimeoutException {
      throw const ApiFailure(
        kind: ApiFailureKind.timeout,
        message: '头像上传超时，请检查网络后重试。',
      );
    }
  }

  /// 移除自定义头像，回到预设图案或默认图案。
  Future<UserProfile> removeAvatar() async {
    final data = await _client.deleteJsonObject('/auth/me/avatar');
    return UserProfile.fromJson(data);
  }

  /// Revokes every refresh token, then clears this device's credentials.
  ///
  /// Access tokens are stateless and may remain valid until their short expiry;
  /// the UI must say that explicitly.
  Future<void> logoutAllDevices() async {
    ApiFailure? failure;
    try {
      await _client.sendNoContent(
        () => _client.post<dynamic>('/auth/logout-all'),
      );
    } on ApiFailure catch (error) {
      failure = error;
    } finally {
      await _session.clearUserSession();
    }
    if (failure != null) {
      throw failure;
    }
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _client.sendNoContent(
      () => _client.post<dynamic>(
        '/auth/change-password',
        data: <String, Object?>{
          'currentPassword': currentPassword,
          'newPassword': newPassword,
        },
      ),
    );
  }

  Future<void> deleteAccount(String password) async {
    await _client.sendNoContent(
      () => _client.delete<dynamic>(
        '/auth/me',
        data: <String, Object?>{'password': password},
      ),
    );
    await _session.clearAll();
  }

  Future<EmailCodeResult> sendEmailCode(String email) async {
    final data = await _client.postJsonObject(
      '/email/send-code',
      body: <String, Object?>{
        'email': email.trim(),
        'purpose': 'VERIFY_EMAIL',
      },
    );
    return EmailCodeResult.fromJson(data);
  }

  Future<EmailCodeResult> verifyEmailCode(String email, String code) async {
    final data = await _client.postJsonObject(
      '/email/verify-code',
      body: <String, Object?>{
        'email': email.trim(),
        'code': code.trim(),
        'purpose': 'VERIFY_EMAIL',
      },
    );
    return EmailCodeResult.fromJson(data);
  }

  Future<NoticeInbox> listMessages() async {
    final data = await _client.getJsonObject('/messages');
    return NoticeInbox.fromJson(data);
  }

  Future<NoticeMessage> markMessageRead(String id) async {
    final data = await _client.patchJsonObject(
      '/messages/${Uri.encodeComponent(id)}/read',
    );
    return NoticeMessage.fromJson(data);
  }

  Future<void> markAllMessagesRead() async {
    await _client.sendNoContent(
      () => _client.patch<dynamic>('/messages/read-all'),
    );
  }

  Future<List<FavoriteItem>> listFavorites() async {
    final raw = await _client.getJsonList('/favorites');
    return raw
        .whereType<Map>()
        .map((item) => FavoriteItem.fromJson(item.cast<String, dynamic>()))
        .toList();
  }

  Future<FavoriteItem> addFavorite({
    required String poiId,
    required String poiName,
    String? city,
    String? imageUrl,
  }) async {
    final data = await _client.postJsonObject(
      '/favorites',
      body: <String, Object?>{
        'poiId': poiId,
        'poiName': poiName,
        if (city != null && city.isNotEmpty) 'city': city,
        if (imageUrl != null && imageUrl.isNotEmpty) 'imageUrl': imageUrl,
      },
    );
    return FavoriteItem.fromJson(data);
  }

  /// Removes by attraction id, which is what the detail page knows.
  Future<void> removeFavorite(String poiId) async {
    await _client.sendNoContent(
      () => _client.delete<dynamic>('/favorites/poi/$poiId'),
    );
  }

  /// Stores the issued tokens and returns as soon as the account is usable.
  ///
  /// The trial handover is deliberately *not* part of this: it is a second
  /// round trip that the user does not have to wait for. The login page used to
  /// keep its button spinning until that request answered, which is why a slow
  /// merge looked like a stuck sign in.
  Future<SignInOutcome> _accept(AuthSession auth) async {
    await _session.saveUserSession(
      accessToken: auth.accessToken,
      refreshToken: auth.refreshToken,
    );
    return SignInOutcome(
      user: auth.user,
      mergePending: (await _session.read()).hasAnonymous,
    );
  }

  /// Carries the stored anonymous trial trip over to the signed in account.
  ///
  /// Without a stored trial token this is a no op, so callers can run it on
  /// every sign in. A failure leaves the token in place: the trip may still be
  /// merged if the call is retried.
  Future<AnonymousMergeOutcome> mergeAnonymousTrips() async {
    final anonymousToken = (await _session.read()).anonymousToken;
    if (anonymousToken == null || anonymousToken.isEmpty) {
      return const AnonymousMergeOutcome();
    }
    try {
      // The anonymous token has to be sent explicitly: the session interceptor
      // now prefers the access token, and the merge endpoint only reads the
      // anonymous header.
      await _client
          .postJsonObject(
            '/auth/merge-anonymous',
            headers: <String, dynamic>{
              SessionStore.anonymousHeader: anonymousToken,
            },
          )
          .timeout(mergeTimeout);
      await _session.clearAnonymousToken();
      return const AnonymousMergeOutcome(merged: true);
    } on TimeoutException {
      return AnonymousMergeOutcome(
        failure: ApiFailure(
          kind: ApiFailureKind.timeout,
          message: '匿名行程合并超时，行程仍可从历史记录查看。',
        ),
      );
    } on ApiFailure catch (failure) {
      // The account is usable either way. Report rather than swallow.
      return AnonymousMergeOutcome(failure: failure);
    }
  }
}
