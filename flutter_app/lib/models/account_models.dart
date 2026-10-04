import '../core/network/api_failure.dart';

/// Signed in user. Mirrors `AuthModels.UserSummary`.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.username,
    required this.email,
    required this.emailVerified,
    required this.roles,
    this.nickname,
    this.avatarKey,
    this.avatarUrl,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: _text(json['id']),
        username: _text(json['username']),
        nickname: json['nickname']?.toString(),
        email: _text(json['email']),
        avatarKey: json['avatarKey']?.toString(),
        avatarUrl: json['avatarUrl']?.toString(),
        emailVerified: json['emailVerified'] == true,
        roles: _textList(json['roles']),
      );

  final String id, username, email;
  final String? nickname;
  final String? avatarKey;

  /// 自定义头像的服务端相对路径（`/media/xxx.jpg`）。
  ///
  /// 与 [avatarKey] 是两种来源：这个有值时优先显示它，为空才回落到预设图案。
  /// 存相对路径而不是完整 URL，换域名后历史头像才不会集体失效。
  final String? avatarUrl;

  String get displayName =>
      nickname == null || nickname!.trim().isEmpty ? username : nickname!;

  /// Whether the account confirmed its email. SMTP is a reserved feature, so
  /// this is shown as a status rather than enforced.
  final bool emailVerified;

  final List<String> roles;
}

/// Token pair plus profile, returned by login and register.
class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        accessToken: _text(json['accessToken']),
        refreshToken: _text(json['refreshToken']),
        user: UserProfile.fromJson(_map(json['user'])),
      );

  final String accessToken, refreshToken;
  final UserProfile user;
}

/// Result of signing in.
///
/// Covers the credential exchange only. The anonymous trial handover is a
/// second round trip, so it is reported as [mergePending] instead of being
/// awaited here: the login button must switch to the signed in state as soon as
/// the account exists, not after an optional follow up request answered.
class SignInOutcome {
  const SignInOutcome({required this.user, this.mergePending = false});

  final UserProfile user;

  /// True when an anonymous trial session is still stored, so the handover in
  /// [AccountRepository.mergeAnonymousTrips] still has to run.
  final bool mergePending;
}

/// Result of carrying an anonymous trial session over to an account.
///
/// The account is already usable when this runs, so a failure is a notice and
/// not a failed sign in.
class AnonymousMergeOutcome {
  const AnonymousMergeOutcome({this.merged = false, this.failure});

  /// True when the trial trip was handed over and the token was dropped.
  final bool merged;

  /// Set when the handover was attempted and did not succeed.
  final ApiFailure? failure;

  /// True when there was nothing to hand over.
  bool get nothingToMerge => !merged && failure == null;
}

/// Saved attraction. Mirrors `FavoriteModels.FavoriteResponse`.
class FavoriteItem {
  const FavoriteItem({
    required this.id,
    required this.poiId,
    required this.poiName,
    this.city,
    this.imageUrl,
    this.createdAt,
  });

  factory FavoriteItem.fromJson(Map<String, dynamic> json) => FavoriteItem(
        id: _text(json['id']),
        poiId: _text(json['poiId']),
        poiName: _text(json['poiName']),
        city: json['city']?.toString(),
        imageUrl: json['imageUrl']?.toString(),
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      );

  final String id, poiId, poiName;
  final String? city, imageUrl;
  final DateTime? createdAt;
}

/// Result of sending or verifying a short lived email code.
///
/// `debugCode` is only populated when SMTP is disabled in a non-production
/// environment; the UI must treat it as a development aid, not a normal flow.
class EmailCodeResult {
  const EmailCodeResult({required this.message, this.debugCode});

  factory EmailCodeResult.fromJson(Map<String, dynamic> json) => EmailCodeResult(
        message: _text(json['message']),
        debugCode: json['debugCode']?.toString(),
      );

  final String message;
  final String? debugCode;
}

/// Read only share link for a trip. Mirrors `TripPlanModels.ShareResult`.
class TripShareLink {
  const TripShareLink({
    required this.id,
    required this.token,
    required this.url,
    required this.hideBudget,
    this.expiresAt,
  });

  factory TripShareLink.fromJson(Map<String, dynamic> json) => TripShareLink(
        id: _text(json['id']),
        token: _text(json['token']),
        url: _text(json['url']),
        hideBudget: json['hideBudget'] == true,
        expiresAt: DateTime.tryParse(json['expiresAt']?.toString() ?? ''),
      );

  final String id, token, url;

  /// Whether the shared copy hides per item and total cost.
  final bool hideBudget;

  final DateTime? expiresAt;
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? value.cast<String, dynamic>() : <String, dynamic>{};

String _text(Object? value) => value?.toString() ?? '';

List<String> _textList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value.map((item) => item.toString()).toList();
}
