import 'package:flutter_test/flutter_test.dart';
import 'package:yujian_travel/core/formatters/distance_text.dart';

/// 距离文案。
///
/// 这一条看着琐碎，但「附近」整个功能的说服力就建立在尺度感上：
/// 把 420 米写成「0.4 公里」，人就没法判断"走过去还是打个车"。
void main() {
  test('一公里以内报米', () {
    expect(distanceText(0), '0 米');
    expect(distanceText(420), '420 米');
    expect(distanceText(999), '999 米');
  });

  test('整公里不写小数点', () {
    expect(distanceText(1000), '1 公里');
    expect(distanceText(3000), '3 公里');
  });

  test('超过一公里的零头保留一位小数', () {
    expect(distanceText(1240), '1.2 公里');
    expect(distanceText(12800), '12.8 公里');
  });

  test('异常值按 0 米处理，不在界面上出现负数距离', () {
    expect(distanceText(-5), '0 米');
  });
}
