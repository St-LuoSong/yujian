import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// 定位这一件事的结论。
///
/// 前四个由 [locationReadinessFor] 从「系统总开关 + 权限状态」推出来；
/// 最后一个只可能出现在真正去取坐标之后 —— 权限都给了、定位服务也开着，
/// 但设备就是没能给出一个位置（室内、地下车库、刚开机）。
enum LocationReadiness {
  /// 有权限，可以取坐标。
  ready,

  /// 手机的系统定位总开关是关着的。给没给权限都不重要，弹权限也拿不到坐标。
  serviceOff,

  /// 用户这次拒绝了授权（还能再问一次）。
  refused,

  /// 用户选了「不再询问」——再弹也不会出现系统弹窗，只能去系统设置里改。
  refusedForever,

  /// 权限与服务都就绪，但这次没取到坐标。
  locateFailed,
}

/// 纯判定：把三个布尔值映射成一个结论。
///
/// 抽成不碰任何平台通道的函数，是为了让这条规则能被直接测到 ——
/// 「什么时候该弹权限、什么时候该说人话」是这个功能里最容易写错、
/// 又最难在真机上把每种分支都走一遍的部分。
LocationReadiness locationReadinessFor({
  required bool serviceEnabled,
  required bool granted,
  required bool permanentlyRefused,
}) {
  // 先看总开关：它比权限更靠前，关着的时候连权限弹窗都不该弹。
  if (!serviceEnabled) {
    return LocationReadiness.serviceOff;
  }
  if (granted) {
    return LocationReadiness.ready;
  }
  return permanentlyRefused
      ? LocationReadiness.refusedForever
      : LocationReadiness.refused;
}

/// 一个坐标点。
class LocationFix {
  const LocationFix({required this.lng, required this.lat, this.accuracyMeters});

  final double lng;
  final double lat;

  /// 系统给出的水平精度（米）。只用于界面上的"大致准确度"提示，
  /// 不参与任何距离计算 —— 服务端算的是点到景点的直线距离。
  final double? accuracyMeters;
}

/// 一次定位尝试的完整结果。
class LocationAttempt {
  const LocationAttempt({
    required this.readiness,
    this.fix,
    this.message = '',
  });

  final LocationReadiness readiness;

  /// 只有真的拿到坐标时才非空。
  final LocationFix? fix;

  /// 给用户看的一句话。成功拿到坐标时为空串。
  final String message;

  bool get hasFix => fix != null;

  /// 这一次是不是"用户自己的选择挡住了我们"。
  ///
  /// 界面据此把重点从"重试定位"挪到"先按城市浏览" ——
  /// 拒绝授权之后还在那里推销定位权限，是最招人烦的一种设计。
  bool get blockedByPermission =>
      readiness == LocationReadiness.refused ||
      readiness == LocationReadiness.refusedForever;
}

/// 设备定位。
///
/// 只做一件事：把 geolocator 的状态归一成 [LocationAttempt]，并把中文说清楚。
/// 它不缓存坐标、不写日志、不上报 —— 位置只活在这一屏，离开即丢。
class LocationService {
  const LocationService();

  /// 取坐标的超时。
  ///
  /// 15 秒是"走到窗边再试一次"的量级；再长用户就会以为应用卡死了，
  /// 而这个页面本来就有替代路径，没必要为了一个坐标把人按住不放。
  static const Duration timeout = Duration(seconds: 15);

  /// 兜底的一次粗定位。走网络/基站，室内和模拟器上更容易出结果，
  /// 「三公里内有什么」这个精度足够。
  static const Duration coarseTimeout = Duration(seconds: 8);

  Future<LocationAttempt> currentFix() async {
    final bool serviceEnabled;
    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
    } on Object {
      return const LocationAttempt(
        readiness: LocationReadiness.locateFailed,
        message: '这台设备没有可用的定位能力，可以先用城市浏览。',
      );
    }

    final LocationPermission permission;
    try {
      permission = await _resolvePermission();
    } on Object {
      return const LocationAttempt(
        readiness: LocationReadiness.locateFailed,
        message: '没能读到定位权限状态，可以先用城市浏览。',
      );
    }

    switch (locationReadinessFor(
      serviceEnabled: serviceEnabled,
      granted: permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always,
      permanentlyRefused: permission == LocationPermission.deniedForever,
    )) {
      case LocationReadiness.serviceOff:
        return const LocationAttempt(
          readiness: LocationReadiness.serviceOff,
          message: '手机的系统定位开关是关着的。打开之后回来点一次「重新定位」就行。',
        );
      case LocationReadiness.refusedForever:
        return const LocationAttempt(
          readiness: LocationReadiness.refusedForever,
          message: '定位权限已被永久拒绝，需要到系统设置里为「豫见智旅」打开。'
              '不打开也能用 —— 下面可以按城市浏览。',
        );
      case LocationReadiness.refused:
        return const LocationAttempt(
          readiness: LocationReadiness.refused,
          message: '没有拿到定位权限。我们不会因为这一条就把页面关掉 ——'
              '可以按城市浏览，或者稍后再点一次「重新定位」。',
        );
      case LocationReadiness.ready:
      case LocationReadiness.locateFailed:
        break;
    }

    // 1) 先问"上一次已知位置"。这条几乎立刻返回，能省掉一整个 GPS 冷启动：
    //    刚从地图/其它应用切过来、模拟器已经喂过坐标时，基本都有值。
    //    读不到不算错误，继续走实时定位。
    try {
      final Position? last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        return LocationAttempt(
          readiness: LocationReadiness.ready,
          fix: LocationFix(
            lng: last.longitude,
            lat: last.latitude,
            accuracyMeters: last.accuracy,
          ),
        );
      }
    } on Object {
      // 忽略：下面还有两条路。
    }

    // 2) 实时定位，中等精度。
    try {
      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          // 三公里半径的判断不需要米级精度：medium 更快、更省电，
          // 而且在室内更容易出结果。
          accuracy: LocationAccuracy.medium,
          timeLimit: timeout,
        ),
      );
      return LocationAttempt(
        readiness: LocationReadiness.ready,
        fix: LocationFix(
          lng: position.longitude,
          lat: position.latitude,
          accuracyMeters: position.accuracy,
        ),
      );
    } on TimeoutException {
      // 3) 再给一次机会：换成低精度（网络/基站），室内更容易出结果。
      try {
        final Position coarse = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: coarseTimeout,
          ),
        );
        return LocationAttempt(
          readiness: LocationReadiness.ready,
          fix: LocationFix(
            lng: coarse.longitude,
            lat: coarse.latitude,
            accuracyMeters: coarse.accuracy,
          ),
        );
      } on Object {
        return const LocationAttempt(
          readiness: LocationReadiness.locateFailed,
          message: '两次都没取到坐标。室内、地下车库，或者模拟器还没设置位置时都会这样 ——'
              '走到窗边再点一次「重新定位」，或者直接用下面「按城市浏览景点」。',
        );
      }
    } on Object {
      return const LocationAttempt(
        readiness: LocationReadiness.locateFailed,
        message: '这次没能取到坐标。可以重试，或者先按城市浏览。',
      );
    }
  }

  /// 权限状态。
  ///
  /// 只在 `denied` 时弹一次系统弹窗：`deniedForever` 再弹也不会有弹窗出现，
  /// 悄悄什么都不发生比明说"要去设置里改"更让人困惑。
  Future<LocationPermission> _resolvePermission() async {
    final LocationPermission current = await Geolocator.checkPermission();
    if (current != LocationPermission.denied) {
      return current;
    }
    return Geolocator.requestPermission();
  }

  /// 打开系统设置。永久拒绝之后唯一的出路。
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  /// 打开系统的定位总开关面板（部分机型直接跳到定位设置页）。
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
}
