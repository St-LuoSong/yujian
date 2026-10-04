import 'package:flutter/services.dart';

import '../../models/app_update_models.dart';

abstract interface class AppReleasePlatform {
  Future<InstalledAppInfo> installedInfo();

  Future<bool> openDownload(String url);
}

class AndroidAppReleasePlatform implements AppReleasePlatform {
  const AndroidAppReleasePlatform();

  static const MethodChannel _channel =
      MethodChannel('com.yujian.travel/app_release');

  @override
  Future<InstalledAppInfo> installedInfo() async {
    final Map<Object?, Object?>? data =
        await _channel.invokeMapMethod<Object?, Object?>('installedInfo');
    if (data == null) {
      throw StateError('无法读取当前应用版本');
    }
    return InstalledAppInfo(
      packageName: data['packageName']?.toString() ?? '',
      versionName: data['versionName']?.toString() ?? '',
      versionCode: int.tryParse(data['versionCode']?.toString() ?? '') ?? 0,
      certificateSha256: data['certificateSha256']?.toString() ?? '',
      debuggable: data['debuggable'] == true,
    );
  }

  @override
  Future<bool> openDownload(String url) async =>
      await _channel.invokeMethod<bool>('openDownload', <String, String>{
        'url': url,
      }) ??
      false;
}
