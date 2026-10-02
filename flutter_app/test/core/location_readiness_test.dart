import 'package:flutter_test/flutter_test.dart';
import 'package:yujian_travel/core/location/location_service.dart';

/// 定位的判定规则。
///
/// 这些用例守着一件事：**拒绝授权不该把人关在门外**，
/// 而"该重试"和"该去系统设置"是两种完全不同的引导，不能混成一个按钮。
void main() {
  group('locationReadinessFor', () {
    test('系统定位开关关着时，即使已经给了权限也算不可用', () {
      expect(
        locationReadinessFor(
          serviceEnabled: false,
          granted: true,
          permanentlyRefused: false,
        ),
        LocationReadiness.serviceOff,
      );
    });

    test('系统开关关着时不该先去要权限：弹了也拿不到坐标', () {
      expect(
        locationReadinessFor(
          serviceEnabled: false,
          granted: false,
          permanentlyRefused: false,
        ),
        LocationReadiness.serviceOff,
      );
    });

    test('有权限且服务开着，就可以取坐标', () {
      expect(
        locationReadinessFor(
          serviceEnabled: true,
          granted: true,
          permanentlyRefused: false,
        ),
        LocationReadiness.ready,
      );
    });

    test('这一次拒绝了授权：还能再问一次', () {
      expect(
        locationReadinessFor(
          serviceEnabled: true,
          granted: false,
          permanentlyRefused: false,
        ),
        LocationReadiness.refused,
      );
    });

    test('永久拒绝：再弹也不会有系统弹窗，只能去系统设置', () {
      expect(
        locationReadinessFor(
          serviceEnabled: true,
          granted: false,
          permanentlyRefused: true,
        ),
        LocationReadiness.refusedForever,
      );
    });

    test('已经拿到权限时，以权限为准', () {
      expect(
        locationReadinessFor(
          serviceEnabled: true,
          granted: true,
          permanentlyRefused: true,
        ),
        LocationReadiness.ready,
      );
    });
  });

  group('LocationAttempt', () {
    test('没有坐标且是权限问题：界面该换个重心', () {
      const LocationAttempt attempt = LocationAttempt(
        readiness: LocationReadiness.refused,
        message: '没有定位权限。',
      );

      expect(attempt.hasFix, isFalse);
      expect(attempt.blockedByPermission, isTrue);
    });

    test('取坐标失败不算权限问题：该给的是"重试"，不是"去设置"', () {
      const LocationAttempt attempt = LocationAttempt(
        readiness: LocationReadiness.locateFailed,
        message: '定位超时了。',
      );

      expect(attempt.hasFix, isFalse);
      expect(attempt.blockedByPermission, isFalse);
    });

    test('系统开关关着是环境问题，同样不是"用户不给你权限"', () {
      const LocationAttempt attempt = LocationAttempt(
        readiness: LocationReadiness.serviceOff,
        message: '定位开关是关着的。',
      );

      expect(attempt.blockedByPermission, isFalse);
    });

    test('拿到坐标时不该再带一句解释文案', () {
      const LocationAttempt attempt = LocationAttempt(
        readiness: LocationReadiness.ready,
        fix: LocationFix(lng: 113.6254, lat: 34.7466),
      );

      expect(attempt.hasFix, isTrue);
      expect(attempt.message, isEmpty);
      expect(attempt.blockedByPermission, isFalse);
    });
  });
}
