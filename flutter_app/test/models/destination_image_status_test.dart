import 'package:flutter_test/flutter_test.dart';
import 'package:yujian_travel/models/travel_models.dart';

/// 详情页"图片来源"这一节的行为。
///
/// 这一节存在的意义不是好看，而是**不让游客把占位图当成河南实拍**。
/// 所以四种配图状态都要有确定的话术，缺图与来源未登记也不能什么都不说。
Destination _destination({
  String imageCredit = '',
  String sourceUrl = '',
  String imageStatus = '',
}) =>
    Destination(
      id: 'longmen',
      name: '龙门石窟',
      city: '洛阳',
      theme: '人文古迹',
      image: 'https://example.test/longmen.jpg',
      summary: '一壁看尽千年风物。',
      ticket: 90,
      duration: '3—4小时',
      audience: '历史文化爱好者',
      weatherTip: '雨天仍可游览。',
      imageCredit: imageCredit,
      sourceUrl: sourceUrl,
      imageStatus: imageStatus,
    );

void main() {
  test('已登记授权的实景图不贴任何标签', () {
    final destination = _destination(
      imageCredit: '豫见智旅运营台 · 已授权实景图',
      sourceUrl: 'https://www.lmsk.gov.cn/',
      imageStatus: Destination.statusRegistered,
    );

    expect(destination.imageNotice, isEmpty);
    expect(destination.showsImageSourceSection, isTrue);
  });

  test('占位示例图明确说明不是河南实景', () {
    final destination = _destination(
      imageCredit: '占位示例图（Unsplash）',
      imageStatus: Destination.statusPlaceholder,
    );

    expect(destination.imageNotice, contains('非河南实景'));
  });

  test('缺图时也显示这一节，而不是整节消失', () {
    // 整节消失等于把"这个景点还没配图"藏起来，游客只会以为加载失败。
    final destination = _destination(imageStatus: Destination.statusMissing);

    expect(destination.imageNotice, contains('暂未配图'));
    expect(destination.showsImageSourceSection, isTrue);
  });

  test('来源未登记时提示补登记', () {
    final destination = _destination(imageStatus: Destination.statusUnlicensed);

    expect(destination.imageNotice, contains('待运营台登记'));
    expect(destination.showsImageSourceSection, isTrue);
  });

  test('旧版本服务端不下发状态时保持原样，不凭空提示', () {
    final destination = _destination(imageCredit: '某摄影师（已授权）');

    expect(destination.imageStatus, isEmpty);
    expect(destination.imageNotice, isEmpty);
    expect(destination.showsImageSourceSection, isTrue);
  });

  test('什么都没有时整节不出现', () {
    final destination = _destination();

    expect(destination.showsImageSourceSection, isFalse);
  });
}
