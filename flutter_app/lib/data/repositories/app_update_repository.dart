import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../core/platform/app_release_platform.dart';
import '../../models/app_update_models.dart';

class AppUpdateRepository {
  AppUpdateRepository({
    required ApiClient client,
    required AppConfig config,
    required AppReleasePlatform platform,
  })  : _client = client,
        _config = config,
        _platform = platform;

  final ApiClient _client;
  final AppConfig _config;
  final AppReleasePlatform _platform;

  Future<AppUpdateInfo> check() async {
    final InstalledAppInfo installed = await _platform.installedInfo();
    final data = await _client.getJsonObject(
      '/app-releases/check',
      query: <String, dynamic>{
        'packageName': installed.packageName,
        'versionCode': installed.versionCode,
        // 通道必须带上：正式包与调试包是两条互不相通的发布线，服务端只在自己
        // 那条线上找版本。漏掉这个参数，调试包用户会永远得到"服务端暂未发布"。
        'channel': installed.debuggable ? 'DEBUG' : 'RELEASE',
      },
    );
    final AppUpdateInfo update = AppUpdateInfo.fromJson(data);
    final Set<String> trusted = (update.trustedCertificateSha256.isEmpty
            ? <String>[update.signingCertificateSha256]
            : update.trustedCertificateSha256)
        .map(_fingerprint)
        .where((value) => value.isNotEmpty)
        .toSet();
    if (!installed.debuggable &&
        update.releaseAvailable &&
        trusted.isNotEmpty &&
        !trusted.contains(_fingerprint(installed.certificateSha256))) {
      return update.withSignatureMismatch();
    }
    return update;
  }

  Future<bool> openDownload(AppUpdateInfo update) {
    final String url = _config.resolveMediaUrl(update.downloadUrl);
    if (url.isEmpty) return Future<bool>.value(false);
    return _platform.openDownload(url);
  }

  /// 把"我现在装着哪个版本"回执给服务端。
  ///
  /// 服务端据此在消息中心留一条一次性更新说明（同一次更新只会留一条）。
  /// 失败一律吞掉：这是启动时的顺手动作，网络不好不该让任何页面变红。
  Future<void> acknowledge() async {
    try {
      final InstalledAppInfo installed = await _platform.installedInfo();
      await _client.sendNoContent(
        () => _client.post<dynamic>(
          '/app-releases/ack',
          query: <String, dynamic>{
            'packageName': installed.packageName,
            'versionCode': installed.versionCode,
            'channel': installed.debuggable ? 'DEBUG' : 'RELEASE',
          },
        ),
      );
    } on Object {
      // 静默：回执不是用户操作，失败就等下一次启动。
    }
  }
}

String _fingerprint(String value) =>
    value.replaceAll(':', '').trim().toLowerCase();
