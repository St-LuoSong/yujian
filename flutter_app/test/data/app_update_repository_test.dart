import 'package:flutter_test/flutter_test.dart';
import 'package:yujian_travel/core/network/api_client.dart';
import 'package:yujian_travel/core/platform/app_release_platform.dart';
import 'package:yujian_travel/data/repositories/app_update_repository.dart';
import 'package:yujian_travel/models/app_update_models.dart';

import '../support/test_http.dart';

void main() {
  test('版本检查发送真实包名和 versionCode，并解析强制更新策略', () async {
    final RecordingAdapter adapter = RecordingAdapter((options, _) async {
      expect(options.path, '/app-releases/check');
      expect(options.queryParameters, <String, Object>{
        'packageName': 'com.yujian.travel',
        'versionCode': 12,
        'channel': 'RELEASE',
      });
      return jsonBody(<String, Object?>{
        'releaseAvailable': true,
        'updateAvailable': true,
        'updateRequired': true,
        'latestVersionCode': 20,
        'latestVersionName': '0.2.0',
        'minimumSupportedVersionCode': 15,
        'releaseTitle': '安全更新',
        'releaseNotes': '修复版本兼容问题',
        'downloadUrl': '/api/app-releases/id/download',
        'fileSize': 1024,
        'fileSha256': 'abc',
        'signingCertificateSha256': 'def',
        'publishedAt': '2026-10-03T02:00:00Z',
      });
    });
    final FakeReleasePlatform platform = FakeReleasePlatform();
    final AppUpdateRepository repository = AppUpdateRepository(
      client: ApiClient(dioWith(adapter)),
      config: testConfig,
      platform: platform,
    );

    final AppUpdateInfo result = await repository.check();

    expect(result.updateRequired, isTrue);
    expect(result.latestVersionCode, 20);
  });

  test('调试包必须按调试通道查询，否则永远看不到只发布了调试包的新版本', () async {
    final RecordingAdapter adapter = RecordingAdapter((options, _) async {
      expect(options.path, '/app-releases/check');
      // 这是本项目真机上真实踩过的坑：不带 channel 时服务端按正式通道查，
      // 而管理台发布的调试包在另一条线上，结果就是"明明发布了却检测不到"。
      expect(options.queryParameters['channel'], 'DEBUG');
      return jsonBody(<String, Object?>{'releaseAvailable': false});
    });
    final AppUpdateRepository repository = AppUpdateRepository(
      client: ApiClient(dioWith(adapter)),
      config: testConfig,
      platform: FakeReleasePlatform(debuggable: true),
    );

    await repository.check();
  });

  test('下载相对地址按 API 主机补全后才交给 Android', () async {
    final FakeReleasePlatform platform = FakeReleasePlatform();
    final AppUpdateRepository repository = AppUpdateRepository(
      client: ApiClient(dioWith(RecordingAdapter((_, __) async => jsonBody(<String, Object>{})))),
      config: testConfig,
      platform: platform,
    );

    await repository.openDownload(const AppUpdateInfo(
      releaseAvailable: true,
      updateAvailable: true,
      updateRequired: false,
      latestVersionCode: 2,
      latestVersionName: '0.2.0',
      minimumSupportedVersionCode: 1,
      releaseTitle: '更新',
      releaseNotes: '说明',
      downloadUrl: '/api/app-releases/id/download',
      fileSize: 1,
      fileSha256: 'a',
      signingCertificateSha256: 'b',
    ));

    expect(platform.openedUrl, 'https://api.example.test/api/app-releases/id/download');
  });

  test('正式包签名与发布证书不一致时，即使版本相同也必须阻断', () async {
    final RecordingAdapter adapter = RecordingAdapter((_, __) async => jsonBody(<String, Object?>{
          'releaseAvailable': true,
          'updateAvailable': false,
          'updateRequired': false,
          'latestVersionCode': 12,
          'latestVersionName': '0.1.0',
          'minimumSupportedVersionCode': 1,
          'releaseTitle': '当前版本',
          'releaseNotes': '无需更新',
          'downloadUrl': '/api/app-releases/id/download',
          'fileSize': 1024,
          'fileSha256': 'abc',
          'signingCertificateSha256': 'official',
        }));
    final AppUpdateRepository repository = AppUpdateRepository(
      client: ApiClient(dioWith(adapter)),
      config: testConfig,
      platform: FakeReleasePlatform(certificateSha256: 'unexpected'),
    );

    final AppUpdateInfo result = await repository.check();

    expect(result.signatureMismatch, isTrue);
    expect(result.updateRequired, isTrue);
  });
}

class FakeReleasePlatform implements AppReleasePlatform {
  FakeReleasePlatform({
    this.certificateSha256 = 'def',
    this.debuggable = false,
  });

  final String certificateSha256;
  final bool debuggable;
  String? openedUrl;

  @override
  Future<InstalledAppInfo> installedInfo() async => InstalledAppInfo(
        packageName: 'com.yujian.travel',
        versionName: '0.1.0',
        versionCode: 12,
        certificateSha256: certificateSha256,
        debuggable: debuggable,
      );

  @override
  Future<bool> openDownload(String url) async {
    openedUrl = url;
    return true;
  }
}
