class InstalledAppInfo {
  const InstalledAppInfo({
    required this.packageName,
    required this.versionName,
    required this.versionCode,
    required this.certificateSha256,
    required this.debuggable,
  });

  final String packageName;
  final String versionName;
  final int versionCode;
  final String certificateSha256;
  final bool debuggable;
}

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.releaseAvailable,
    required this.updateAvailable,
    required this.updateRequired,
    required this.latestVersionCode,
    required this.latestVersionName,
    required this.minimumSupportedVersionCode,
    required this.releaseTitle,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.fileSize,
    required this.fileSha256,
    required this.signingCertificateSha256,
    this.trustedCertificateSha256 = const <String>[],
    this.publishedAt,
    this.signatureMismatch = false,
  });

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) => AppUpdateInfo(
        releaseAvailable: json['releaseAvailable'] == true,
        updateAvailable: json['updateAvailable'] == true,
        updateRequired: json['updateRequired'] == true,
        latestVersionCode: _integer(json['latestVersionCode']),
        latestVersionName: json['latestVersionName']?.toString() ?? '',
        minimumSupportedVersionCode:
            _integer(json['minimumSupportedVersionCode']),
        releaseTitle: json['releaseTitle']?.toString() ?? '',
        releaseNotes: json['releaseNotes']?.toString() ?? '',
        downloadUrl: json['downloadUrl']?.toString() ?? '',
        fileSize: _integer(json['fileSize']),
        fileSha256: json['fileSha256']?.toString() ?? '',
        signingCertificateSha256:
            json['signingCertificateSha256']?.toString() ?? '',
        trustedCertificateSha256: _textList(json['trustedCertificateSha256']),
        publishedAt: DateTime.tryParse(json['publishedAt']?.toString() ?? ''),
      );

  final bool releaseAvailable;
  final bool updateAvailable;
  final bool updateRequired;
  final int latestVersionCode;
  final String latestVersionName;
  final int minimumSupportedVersionCode;
  final String releaseTitle;
  final String releaseNotes;
  final String downloadUrl;
  final int fileSize;
  final String fileSha256;
  final String signingCertificateSha256;
  final List<String> trustedCertificateSha256;
  final DateTime? publishedAt;
  final bool signatureMismatch;

  AppUpdateInfo withSignatureMismatch() => AppUpdateInfo(
        releaseAvailable: releaseAvailable,
        updateAvailable: true,
        updateRequired: true,
        latestVersionCode: latestVersionCode,
        latestVersionName: latestVersionName,
        minimumSupportedVersionCode: minimumSupportedVersionCode,
        releaseTitle: releaseTitle,
        releaseNotes: releaseNotes,
        downloadUrl: downloadUrl,
        fileSize: fileSize,
        fileSha256: fileSha256,
        signingCertificateSha256: signingCertificateSha256,
        trustedCertificateSha256: trustedCertificateSha256,
        publishedAt: publishedAt,
        signatureMismatch: true,
      );
}

int _integer(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

List<String> _textList(Object? value) {
  if (value is! List) return const <String>[];
  return value.map((item) => item.toString()).where((item) => item.isNotEmpty).toList();
}
